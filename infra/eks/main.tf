provider "aws" {
  region = local.region
}

data "aws_availability_zones" "available" {
  # Exclude local zones
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  name               = "meetup-${basename(path.cwd)}"
  kubernetes_version = "1.33"
  region             = "us-east-1"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Test       = local.name
    GithubRepo = "terraform-aws-eks"
    GithubOrg  = "terraform-aws-modules"
  }
}

################################################################################
# Polices
################################################################################

data "aws_iam_policy_document" "external_dns" {
  statement {
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/*"]
  }
  statement {
    actions   = ["route53:ListHostedZones","route53:ListResourceRecordSets","route53:ListTagsForResources"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "external_dns" {
  name = "${local.name}-external-dns"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = ["sts:AssumeRole","sts:TagSession"]
      }
    ]
  })
}


resource "aws_iam_role_policy" "external_dns" {
  name   = "${local.name}-external-dns-policy"
  role   = aws_iam_role.external_dns.id
  policy = data.aws_iam_policy_document.external_dns.json
}

# resource "aws_eks_pod_identity_association" "external_dns" {
#   cluster_name    = module.eks.cluster_name
#   namespace       = "external-dns"
#   service_account = "external-dns"
#   role_arn        = aws_iam_role.external_dns.arn
# }

################################################################################
# EKS Module
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.1.5"

  name                   = local.name
  kubernetes_version     = local.kubernetes_version
  endpoint_public_access = true
  deletion_protection    = true

  enable_cluster_creator_admin_permissions = true

  compute_config = {
    enabled    = true
    node_pools = ["general-purpose"]
  }

  addons = {
    metrics-server = { most_recent = true }
    cert-manager  = { most_recent = true }
    external-dns   = {
      most_recent = true
      configuration_values = jsonencode({
        domainFilters = ["arcanjoconsultoria.com.br"] # ajuste para seu domínio
        txtOwnerId  = local.name
      })
      pod_identity_association = [
      {
        service_account = "external-dns"
        role_arn        = aws_iam_role.external_dns.arn
      }
    ]
    }
  }


  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  tags = local.tags
}

module "disabled_eks" {
  source = "terraform-aws-modules/eks/aws"
  version = "21.1.5"

  create = false
}

################################################################################
# Supporting Resources
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]
  intra_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 52)]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}