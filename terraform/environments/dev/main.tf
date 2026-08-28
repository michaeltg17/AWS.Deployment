module "vpc" {
  source = "../../modules/vpc"

  name                 = local.name
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

  tags = local.tags
}

module "eks" {
  source = "../../modules/eks"

  name                  = local.name
  region                = var.aws_region
  kubernetes_version    = var.kubernetes_version
  vpc_id                = module.vpc.vpc_id
  vpc_cidr              = module.vpc.vpc_cidr
  private_subnet_ids    = module.vpc.private_subnet_ids
  worker_instance_types = var.worker_instance_types
  worker_disk_size_gb   = var.worker_disk_size_gb
  worker_min_size       = var.worker_min_size
  worker_max_size       = var.worker_max_size
  worker_desired_size   = var.worker_desired_size
  github_repo           = "michaeltg17/Template.Deployment"

  tags = local.tags
}

module "rds" {
  source = "../../modules/rds"

  name                       = "${local.name}-db"
  engine_version             = var.db_engine_version
  instance_class             = var.db_instance_class
  master_password            = var.db_master_password
  multi_az                   = var.db_multi_az
  vpc_id                     = module.vpc.vpc_id
  private_subnet_ids         = module.vpc.private_subnet_ids
  vpc_cidr                   = module.vpc.vpc_cidr
  allowed_security_group_ids = [module.eks.node_security_group_id]

  tags = local.tags
}

# Note: the aws-auth ConfigMap (node role -> system:node) is applied by
# bootstrap/setup-eks.sh with kubectl, not here. The kubernetes provider
# cannot plan kubernetes_manifest before the cluster exists (its
# cluster_ca_certificate is unknown at plan time).
