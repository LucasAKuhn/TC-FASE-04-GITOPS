output "repository_urls" {
  description = "Lista com os URLs de todos os repositórios criados"
  value       = aws_ecr_repository.repos[*].repository_url
}