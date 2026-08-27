output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "EKS API endpoint (private)"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded cluster CA certificate"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "Cluster API security group id"
  value       = aws_security_group.cluster.id
}

output "node_security_group_id" {
  description = "Worker node security group id"
  value       = aws_security_group.node.id
}

output "node_group_arn" {
  description = "Managed node group ARN"
  value       = aws_eks_node_group.this.arn
}

output "node_role_arn" {
  description = "Worker node IAM role ARN"
  value       = aws_iam_role.node.arn
}

output "ci_role_arn" {
  description = "GitHub Actions OIDC role ARN (set as AWS_ROLE_ARN_<env> repo secret)"
  value       = aws_iam_role.ci.arn
}

output "alb_controller_role_arn" {
  description = "IRSA role for the load balancer controller (used by bootstrap/setup-eks.sh)"
  value       = aws_iam_role.alb_controller.arn
}
