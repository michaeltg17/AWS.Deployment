locals {
  tags = var.tags
}

resource "aws_db_subnet_group" "this" {
  name_prefix = "${var.name}-"
  subnet_ids  = var.private_subnet_ids

  tags = merge(local.tags, { Name = var.name })
}

resource "aws_security_group" "this" {
  name_prefix = "${var.name}-"
  description = "RDS PostgreSQL"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.allowed_security_group_ids

    content {
      description     = "PostgreSQL from EKS nodes"
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = [ingress.value]
    }
  }

  # EKS managed node groups attach EKS-managed SGs to node ENIs (not the node
  # SG above), so also allow the whole VPC - the DB is private and only
  # reachable from within the VPC anyway.
  dynamic "ingress" {
    for_each = var.vpc_cidr != "" ? [var.vpc_cidr] : []

    content {
      description = "PostgreSQL from within the VPC (EKS nodes)"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    description = "allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = var.name })

  lifecycle {
    ignore_changes = [name]
  }
}

resource "aws_db_instance" "this" {
  identifier = var.name

  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage_gb
  max_allocated_storage = var.max_allocated_storage_gb
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.master_username
  password = var.master_password

  multi_az = var.multi_az

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  publicly_accessible    = false

  # dev: apply changes immediately, no final snapshot on destroy
  apply_immediately       = true
  backup_retention_period = 1
  deletion_protection     = false
  skip_final_snapshot     = true

  tags = merge(local.tags, { Name = var.name })
}
