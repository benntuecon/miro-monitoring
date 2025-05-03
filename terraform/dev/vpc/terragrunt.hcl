include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "terraform-aws-modules/vpc/aws//."
  # Lock to a specific version for stability
  # Check the Terraform Registry for the latest version: https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest
  # version = "5.8.1"
}

dependency "account" {
  config_path = "../.."
  mock_outputs = {
    aws_account_id = "123456789012" # Mock output for planning if needed
  }
}

inputs = {
  name = "miro-vpc-${get_env("TF_VAR_environment", "dev")}" # Use environment variable or default
  cidr = local.env.vpc_cidr

  azs             = ["${local.env.aws_region}a", "${local.env.aws_region}b"] # Use at least two AZs for availability
  private_subnets = local.env.private_subnets
  public_subnets  = local.env.public_subnets

  enable_nat_gateway = true
  single_nat_gateway = false # Use one NAT gateway per AZ for high availability
  one_nat_gateway_per_az = true # Ensure NAT gateway per AZ

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(
    local.env.tags,
    {
      "Name" = "miro-vpc-${local.env.environment}"
    }
  )

  # Public subnet tags (optional, but good practice)
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  # Private subnet tags (optional, but good practice)
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# Expose locals from the included env.hcl file
locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}
