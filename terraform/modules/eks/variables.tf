variable "vpc_id" {
  description = "ID da VPC principal"
  type        = string
}

variable "public_subnets" {
  description = "Lista de subnets públicas para o EKS"
  type        = list(string)
}

variable "private_subnets" {
  description = "Lista de subnets privadas para o EKS e DB"
  type        = list(string)
}

variable "labrole_arn" {
  description = "ARN da LabRole do AWS Academy"
  type        = string
}