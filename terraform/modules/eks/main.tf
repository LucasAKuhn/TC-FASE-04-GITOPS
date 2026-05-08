# Criação do Cluster EKS
resource "aws_eks_cluster" "main" {
  name     = "tm-eks-cluster-01"
  role_arn = var.labrole_arn

  vpc_config {
    subnet_ids              = concat(var.public_subnets, var.private_subnets)
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  # Aumenta o tempo limite para evitar erros de timeout em laboratórios lentos
  timeouts {
    create = "60m"
    delete = "60m"
  }
}

# Criação do Node Group (Máquinas do Cluster)
resource "aws_eks_node_group" "nodes" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "tm-eks-ng-01"
  node_role_arn   = var.labrole_arn
  
  # Apenas subnets privadas como solicitado no roteiro "A lista vai mostrar as 6 subnets. Desmarque as Públicas."
  subnet_ids      = var.private_subnets

  # Downsizing para poupar os créditos do laboratório
  instance_types = ["t3.small"]

  scaling_config {
    desired_size = 5
    max_size     = 5
    min_size     = 1
  }

  # Aumenta o tempo limite para o node group (120m no destroy para EKS demorado)
  timeouts {
    create = "60m"
    delete = "120m"
  }

  # Garante que o Node Group só é criado depois do Cluster estar pronto
  depends_on = [
    aws_eks_cluster.main
  ]
}

# --- ATIVAÇÃO DO IRSA (OIDC PROVIDER) ---
# Necessário para que o K8s emita tokens em vez de base64 text secrets
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# resource "aws_iam_openid_connect_provider" "eks" {
#   client_id_list  = ["sts.amazonaws.com"]
#   thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
#   url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
# }