resource "aws_sqs_queue" "main_queue" {
  name = "analytics-service-sqs"
}