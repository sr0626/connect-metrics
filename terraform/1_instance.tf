locals {
  ctr-stream = "${var.instance_alias}-ctr-stream"
  ae-stream  = "${var.instance_alias}-ae-stream"

  kinesis_stream_arns = {
    ctr   = aws_kinesis_stream.ctr.arn
    agent = aws_kinesis_stream.agent.arn
  }
}

resource "aws_connect_instance" "test" {
  identity_management_type  = "CONNECT_MANAGED"
  inbound_calls_enabled     = true
  instance_alias            = var.instance_alias
  outbound_calls_enabled    = true
  contact_flow_logs_enabled = true
}

resource "time_sleep" "after_instance" {
  depends_on      = [aws_connect_instance.test]
  create_duration = "45s"
}

# resource "aws_iam_service_linked_role" "connect" {
#   aws_service_name = "connect.amazonaws.com"
# }

data "aws_iam_role" "connect_slr" {
  name = "AWSServiceRoleForAmazonConnect"
  #depends_on = [aws_iam_service_linked_role.connect]
}

data "aws_iam_policy_document" "bucket_policy" {
  statement {
    sid    = "AllowConnectWrites"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:GetBucketLocation",
      "s3:ListBucket"
    ]
    principals {
      type        = "AWS"
      identifiers = [data.aws_iam_role.connect_slr.arn]
    }
    resources = [
      "${aws_s3_bucket.connect_artifacts.arn}",
      "${aws_s3_bucket.connect_artifacts.arn}/*",
      "${aws_s3_bucket.connect_artifacts.arn}/chat_transcripts/*",
      "${aws_s3_bucket.connect_artifacts.arn}/call_recordings/*",
      "${aws_s3_bucket.connect_artifacts.arn}/reports/*"
    ]
  }
}

resource "aws_s3_bucket_policy" "connect_artifacts" {
  bucket = aws_s3_bucket.connect_artifacts.id
  policy = data.aws_iam_policy_document.bucket_policy.json
}

resource "aws_connect_instance_storage_config" "chat_store" {
  #depends_on    = [aws_iam_service_linked_role.connect]
  instance_id   = aws_connect_instance.test.id
  resource_type = "CHAT_TRANSCRIPTS"

  storage_config {
    s3_config {
      bucket_name   = aws_s3_bucket.connect_artifacts.id
      bucket_prefix = "chat_transcripts"

      encryption_config {
        encryption_type = "KMS"
        key_id          = aws_kms_alias.test.target_key_arn
      }
    }

    storage_type = "S3"
  }
}

resource "aws_connect_instance_storage_config" "call_store" {
  #depends_on    = [aws_iam_service_linked_role.connect, aws_s3_bucket_policy.connect_artifacts]
  depends_on    = [aws_s3_bucket_policy.connect_artifacts]
  instance_id   = aws_connect_instance.test.id
  resource_type = "CALL_RECORDINGS"

  storage_config {
    s3_config {
      bucket_name   = aws_s3_bucket.connect_artifacts.id
      bucket_prefix = "call_recordings"

      encryption_config {
        encryption_type = "KMS"
        key_id          = aws_kms_alias.test.target_key_arn
      }
    }

    storage_type = "S3"
  }
}

resource "aws_connect_instance_storage_config" "report_store" {
  #depends_on    = [aws_iam_service_linked_role.connect, aws_s3_bucket_policy.connect_artifacts]
  instance_id   = aws_connect_instance.test.id
  resource_type = "SCHEDULED_REPORTS"

  storage_config {
    s3_config {
      bucket_name   = aws_s3_bucket.connect_artifacts.id
      bucket_prefix = "reports"

      encryption_config {
        encryption_type = "KMS"
        key_id          = aws_kms_alias.test.target_key_arn
      }
    }

    storage_type = "S3"
  }
}

#Kinesis Data Streams for CTR  (can be stream or firehose)
resource "aws_kinesis_stream" "ctr" {
  name             = local.ctr-stream
  shard_count      = 1
  retention_period = 24
  stream_mode_details {
    stream_mode = "PROVISIONED"
  }
}

# TODO Agent Events  - ONLY stream (no firehose support)
resource "aws_kinesis_stream" "agent" {
  name             = local.ae-stream
  shard_count      = 1
  retention_period = 24
  stream_mode_details {
    stream_mode = "PROVISIONED"
  }
}

resource "aws_kinesis_resource_policy" "connect_stream_policy" {
  for_each     = local.kinesis_stream_arns
  resource_arn = each.value

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowConnectPutRecords"
        Effect    = "Allow"
        Principal = { AWS = data.aws_iam_role.connect_slr.arn }
        Action = [
          "kinesis:PutRecord",
          "kinesis:PutRecords",
          "kinesis:DescribeStream",
          "kinesis:DescribeStreamSummary"
        ]
        Resource = each.value
      }
    ]
  })
}

resource "aws_connect_instance_storage_config" "stream_ctr" {
  #depends_on    = [aws_kinesis_resource_policy.connect_stream_policy]
  instance_id   = aws_connect_instance.test.id
  resource_type = "CONTACT_TRACE_RECORDS"

  storage_config {
    storage_type = "KINESIS_STREAM"
    kinesis_stream_config {
      stream_arn = aws_kinesis_stream.ctr.arn
    }
  }
}

#expected resource_type to be one of ["CHAT_TRANSCRIPTS" "CALL_RECORDINGS" "SCHEDULED_REPORTS" "MEDIA_STREAMS" 
#"CONTACT_TRACE_RECORDS" "AGENT_EVENTS" "REAL_TIME_CONTACT_ANALYSIS_SEGMENTS" "ATTACHMENTS" "CONTACT_EVALUATIONS" 
#"SCREEN_RECORDINGS" "REAL_TIME_CONTACT_ANALYSIS_CHAT_SEGMENTS" "REAL_TIME_CONTACT_ANALYSIS_VOICE_SEGMENTS" 
#"EMAIL_MESSAGES"]
resource "aws_connect_instance_storage_config" "stream_agent_events" {
  #depends_on    = [aws_kinesis_resource_policy.connect_stream_policy]
  instance_id   = aws_connect_instance.test.id
  resource_type = "AGENT_EVENTS"

  storage_config {
    storage_type = "KINESIS_STREAM"
    kinesis_stream_config {
      stream_arn = aws_kinesis_stream.agent.arn
    }
  }
}
