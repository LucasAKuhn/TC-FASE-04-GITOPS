locals {
  # Lista dos microsserviços do projeto
  repos = ["auth", "flag", "targeting", "evaluation", "analytics"]
}

resource "aws_ecr_repository" "repos" {
  count                = length(local.repos)
  name                 = "${local.repos[count.index]}-service"
  image_tag_mutability = "MUTABLE"
  force_delete         = true # Facilita a destruição do laboratório
}