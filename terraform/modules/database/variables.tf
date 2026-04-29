variable "vpc_id" {
  description = "ID da VPC principal"
  type        = string
}

variable "private_subnets" {
  description = "Lista de subnets privadas"
  type        = list(string)
}

variable "db_password" {
  description = "Senha master para as instancias RDS PostgreSQL"
  type        = string
  sensitive   = true
}