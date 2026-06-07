provider "aws" { region = "us-east-1" }

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"
  cluster_name = "iicpc-platform"
  cluster_version = "1.29"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets

  eks_managed_node_groups = {
    platform = {
      instance_types = ["t3.medium"]
      min_size = 2; max_size = 10; desired_size = 3
    }
  }
}

resource "helm_release" "redpanda" {
  name       = "redpanda"
  repository = "https://charts.redpanda.com"
  chart      = "redpanda"
  namespace  = "default"
}