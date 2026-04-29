output "eks_cluster_endpoint" {
  description = "Endpoint para comunicação com o cluster Kubernetes"
  value       = module.eks.cluster_endpoint
}

# output "dynamodb_table_name" {
#   description = "Nome da tabela do DynamoDB de Analytics"
#   value       = module.database.dynamodb_table_name
# }

# output "redis_endpoint" {
#   description = "Endpoint de conexão do Redis"
#   value       = module.database.redis_endpoint
# }

# output "postgres_endpoints" {
#   description = "Endereços das instâncias PostgreSQL"
#   value       = module.database.postgres_endpoints
# }

# output "sqs_queue_url" {
#   description = "URL da fila do SQS"
#   value       = module.messaging.sqs_queue_url
# }

output "ecr_repository_urls" {
  description = "URLs dos repositórios ECR criados"
  value       = module.ecr.repository_urls
}