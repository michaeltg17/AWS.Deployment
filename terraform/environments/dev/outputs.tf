output "region" {
  description = "AWS region"
  value       = var.aws_region
}

output "vpc_id" {
  description = "VPC id (used by bootstrap/setup-eks.sh)"
  value       = module.vpc.vpc_id
}

output "cluster_name" {
  description = "EKS cluster name (aws eks update-kubeconfig --name <this>)"
  value       = module.eks.cluster_name
}

output "kubectl_setup" {
  description = "One-liner to point kubectl at the cluster"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --alias ${module.eks.cluster_name}"
}

output "rds_endpoint" {
  description = "RDS private endpoint (put in k8s/environments/<env>.env as RDS_ENDPOINT)"
  value       = module.rds.address
}

output "db_user" {
  description = "RDS master username (put in k8s/environments/<env>.env as DB_USER)"
  value       = module.rds.username
}

output "ci_role_arn" {
  description = "GitHub Actions role ARN (set as AWS_ROLE_ARN_<ENV> repo secret)"
  value       = module.eks.ci_role_arn
}

output "alb_controller_role_arn" {
  description = "IRSA role for the load balancer controller (bootstrap/setup-eks.sh reads it)"
  value       = module.eks.alb_controller_role_arn
}

output "destroy_command" {
  description = "Destroys everything this config created"
  value       = "terraform destroy (run from this directory)"
}
