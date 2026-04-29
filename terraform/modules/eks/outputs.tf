output "cluster_endpoint" {
  description = "Endpoint para comunicação com a API do Kubernetes"
  value       = aws_eks_cluster.main.endpoint
  depends_on  = [aws_eks_node_group.nodes]
}

output "cluster_name" {
  description = "Nome do cluster EKS"
  value       = aws_eks_cluster.main.name
  depends_on  = [aws_eks_node_group.nodes]
}

output "cluster_certificate_authority_data" {
  description = "Certificado de autoridade (Base64) para autenticar provedores Helm e Kubernetes"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  depends_on  = [aws_eks_node_group.nodes]
}