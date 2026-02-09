resource "aws_connect_phone_number" "test" {
  country_code = "US"
  target_arn   = aws_connect_instance.test.arn
  type         = "DID"
}

resource "aws_connect_phone_number_contact_flow_association" "test" {
  phone_number_id = aws_connect_phone_number.test.id
  instance_id     = aws_connect_instance.test.id
  #contact_flow_id = aws_connect_contact_flow.test.contact_flow_id
  contact_flow_id = data.aws_connect_contact_flow.basic.contact_flow_id
}

output "did_number" {
  value = aws_connect_phone_number.test.phone_number
}
