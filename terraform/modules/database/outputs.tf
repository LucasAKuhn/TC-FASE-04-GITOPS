output "postgres_endpoints" {
  description = "Endereços das 3 instâncias PostgreSQL"
  value       = aws_db_instance.postgres[*].address
}

output "redis_endpoint" {
  description = "Endereço do Redis"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "dynamodb_table_name" {
  description = "Nome da tabela do DynamoDB"
  value       = aws_dynamodb_table.analytics.name
}