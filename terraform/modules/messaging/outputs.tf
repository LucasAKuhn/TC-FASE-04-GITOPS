output "sqs_queue_url" {
  description = "URL da fila do SQS"
  value       = aws_sqs_queue.main_queue.url
}