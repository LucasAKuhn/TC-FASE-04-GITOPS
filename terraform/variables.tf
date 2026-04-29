variable "aws_region" {
  description = "Região principal da AWS para o laboratório"
  type        = string
  default     = "us-east-1"
}

variable "github_pat" {
  description = "Personal Access Token do GitHub para o ArgoCD. Passe via export TF_VAR_github_pat"
  type        = string
  sensitive   = true
  default     = "" # Pode ficar vazio na declaracao
}

variable "master_key" {
  description = "Chave Mestra interna para autenticacao JWT/APIs. Obrigatória via: $env:TF_VAR_master_key='<SUA_MASTER_KEY>'"
  type        = string
  sensitive   = true
  # Sem default — exige injecao via TF_VAR_master_key
}

variable "github_repo_url" {
  description = "A URL do seu repositório Git que o ArgoCD deve escutar. Passe via export TF_VAR_github_repo_url"
  type        = string
  # Sem default — exige injecao TF_VAR_github_repo_url
}

variable "service_api_key" {
  description = "Chave de API interna entre servicos (ex: SERVICE_API_KEY do evaluation-service). Obrigatória via: $env:TF_VAR_service_api_key='<SUA_API_KEY>'"
  type        = string
  sensitive   = true
  # Sem default — exige injecao via TF_VAR_service_api_key
}