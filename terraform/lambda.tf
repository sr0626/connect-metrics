locals {
  ctr_stream_arn = aws_kinesis_stream.ctr.arn
  ae_stream_arn  = aws_kinesis_stream.agent.arn
}

resource "aws_iam_role" "lambda" {
  name = "${var.instance_alias}-kds-logger-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda" {
  name = "${var.instance_alias}-kds-logger-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogging"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Sid    = "KinesisAccess"
        Effect = "Allow"
        Action = [
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:DescribeStream",
          "kinesis:ListStreams"
        ]
        Resource = [
          local.ctr_stream_arn,
          local.ae_stream_arn
        ]
      }
    ]
  })
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

# Lambda Functions
resource "aws_lambda_function" "ctr" {
  function_name    = "${var.instance_alias}-ctr"
  role             = aws_iam_role.lambda.arn
  handler          = "kds_handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 30
  depends_on       = [aws_cloudwatch_log_group.ctr]
}

resource "aws_lambda_function" "ae" {
  function_name    = "${var.instance_alias}-ae"
  role             = aws_iam_role.lambda.arn
  handler          = "kds_handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 30
  depends_on       = [aws_cloudwatch_log_group.ae]
}

resource "aws_lambda_function" "ce" {
  function_name    = "${var.instance_alias}-ce"
  role             = aws_iam_role.lambda.arn
  handler          = "ce_handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 30
  depends_on       = [aws_cloudwatch_log_group.ce]
}

# Event Source Mappings
resource "aws_lambda_event_source_mapping" "ctr" {
  event_source_arn  = local.ctr_stream_arn
  function_name     = aws_lambda_function.ctr.arn
  starting_position = "TRIM_HORIZON"
  batch_size        = 100
}

resource "aws_lambda_event_source_mapping" "ae" {
  event_source_arn  = local.ae_stream_arn
  function_name     = aws_lambda_function.ae.arn
  starting_position = "TRIM_HORIZON"
  batch_size        = 100
}


# The below uses EB for Contact event.  It's not possible to use Kinesis for Contact Events like (INITIATED, QUEUED) as of now.
# EventBridge rule to capture Amazon Connect Contact Events
resource "aws_cloudwatch_event_rule" "ce" {
  name        = "${var.instance_alias}-ce"
  description = "Capture Amazon Connect Contact Events"

  event_pattern = jsonencode({
    "source": ["aws.connect"],
    # Matches detail-types like "Amazon Connect Contact Event" (and future variants)
    "detail-type": [{ "prefix": "Amazon Connect Contact" }]
  })
}

resource "aws_cloudwatch_event_target" "ce_target" {
  rule      = aws_cloudwatch_event_rule.ce.name
  target_id = "lambda"
  arn       = aws_lambda_function.ce.arn
}

resource "aws_lambda_permission" "allow_events_connect_contact" {
  statement_id  = "AllowEventBridgeInvoke-ContactEvents"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ce.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ce.arn
}