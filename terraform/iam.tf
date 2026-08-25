# Scoped permissions for terraform deploys of this stack, attached to the
# GitHub OIDC deploy role (below). Local deploys run under the dev account, which needs no policy here.
# Delete/terminate is restricted to resources tagged Project=<project_name>,
# so a botched destroy cannot reach other projects in the account.
# Reads and non-destructive writes are intentionally untagged: the provider
# tags resources only after creating them, so a tag condition on the
# create path would break first applies.

resource "aws_iam_policy" "tf_deploy_dev" {
  name        = "TfDeployDev-AwsDeployment"
  description = "Scoped terraform permissions for the AWS.Deployment dev stack"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "Sts"
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity"]
        Resource = "*"
      },
      {
        Sid    = "EC2Read"
        Effect = "Allow"
        Action = [
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeKeyPairs",
          "ec2:DescribeRouteTables",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeTags",
          "ec2:DescribeVolumes",
          "ec2:DescribeVpcAttribute",
          "ec2:DescribeVpcs",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.aws_region
          }
        }
      },
      {
        Sid    = "EC2Write"
        Effect = "Allow"
        Action = [
          "ec2:AttachInternetGateway",
          "ec2:AttachVolume",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:CreateInternetGateway",
          "ec2:CreateRoute",
          "ec2:CreateRouteTable",
          "ec2:CreateRouteTableAssociation",
          "ec2:CreateSecurityGroup",
          "ec2:CreateSubnet",
          "ec2:CreateTags",
          "ec2:CreateVolume",
          "ec2:CreateVpc",
          "ec2:ModifyVpcAttribute",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:RunInstances",
          "ec2:StartInstances",
          "ec2:StopInstances",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.aws_region
          }
        }
      },
      {
        Sid    = "EC2DeleteTagged"
        Effect = "Allow"
        Action = [
          "ec2:DeleteInternetGateway",
          "ec2:DeleteRoute",
          "ec2:DeleteRouteTable",
          "ec2:DeleteRouteTableAssociation",
          "ec2:DeleteSecurityGroup",
          "ec2:DeleteSubnet",
          "ec2:DeleteTags",
          "ec2:DeleteVolume",
          "ec2:DeleteVpc",
          "ec2:DetachInternetGateway",
          "ec2:DetachVolume",
          "ec2:TerminateInstances",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion"     = var.aws_region
            "aws:ResourceTag/Project" = var.project_name
          }
        }
      },
    ]
  })

  tags = local.tags
}

# GitHub Actions OIDC provider. Account-level singleton (one per account),
# shared by any stack that authenticates GitHub workflows via OIDC.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  tags = local.tags
}

# Role assumed by GitHub Actions when a workflow needs AWS (cd.yml). The
# trust policy is scoped to this repo via the OIDC sub claim, so no other
# repo can assume it.
resource "aws_iam_role" "github_tf_deploy" {
  name = "github-tf-deploy-aws-deployment"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
          }
        }
      },
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "github_tf_deploy" {
  role       = aws_iam_role.github_tf_deploy.name
  policy_arn = aws_iam_policy.tf_deploy_dev.arn
}
