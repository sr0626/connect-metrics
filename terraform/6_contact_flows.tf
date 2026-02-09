# resource "aws_connect_contact_flow" "test" {
#   instance_id  = aws_connect_instance.test.id
#   name         = "My Inbound Flow"
#   description  = "My Inbound Contact Flow"
#   type         = "CONTACT_FLOW"
#   content      = file("${path.module}/../json/contact_flows/MyInboundFlow.json")
#   content_hash = filebase64sha256("${path.module}/../json/contact_flows/MyInboundFlow.json")
# }


data "aws_connect_contact_flow" "basic" {
  instance_id = aws_connect_instance.test.id
  name        = "Sample inbound flow (first contact experience)"
}
