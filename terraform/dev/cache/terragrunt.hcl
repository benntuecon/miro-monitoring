include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "terraform-aws-modules/elasticache/aws//modules/redis"
  # Lock to a specific version for stability
  # Check the Terraform Registry for the latest version: https://registry.terraform.io/modules/terraform-aws-modules/elasticache/aws/latest
  # version = "1.3.0" # Example version, update as needed
}

dependency "vpc" {
  config_path = "../vpc"
  mock_outputs = {
    vpc_id          = "vpc-1234567890abcdef0"
    private_subnets = ["subnet-123", "subnet-456"]
    # Add vpc_cidr_block mock for cache module validation if needed by the specific module version
    vpc_cidr_block  = "10.0.0.0/16"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

# Add dependency on the Lambda module to get its security group ID
dependency "lambda" {
  config_path = "../lambda"
  mock_outputs = {
    lambda_security_group_id = "sg-1234567890abcdef0"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  name        = "miro-cache-${local.env.environment}"
  vpc_id      = dependency.vpc.outputs.vpc_id
  subnets     = dependency.vpc.outputs.private_subnets # Deploy cache in private subnets

  cluster_size          = 1 # Number of nodes in the cluster (1 for single node, >1 for cluster mode disabled replica)
  instance_type         = local.env.cache_node_type
  engine                = "valkey" # Specify Valkey engine
  engine_version        = "7.2" # Specify desired Valkey version explicitly for clarity, ensure it's supported
  # parameter_group_name = aws_elasticache_parameter_group.valkey_default.name # Reference custom parameter group if needed

  # Security Group - Allow traffic ONLY from the Lambda function's security group
  security_group_rules = {
    ingress_lambda = {
      description              = "Allow Valkey access from Lambda Function SG"
      source_security_group_id = dependency.lambda.outputs.lambda_security_group_id # Reference Lambda SG
      # cidr_blocks field is removed as we are using source_security_group_id
      from_port                = 6379 # Default Valkey/Redis port
      to_port                  = 6379
      protocol                 = "tcp"
    }
  }

  # allowed_security_group_ids = [] # Add any other security groups that need access if necessary

  tags = merge(
    local.env.tags,
    {
      "Name" = "miro-cache-${local.env.environment}"
    }
  )
}

# Expose locals from the included env.hcl file
locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

# Potentially define a parameter group if defaults aren't sufficient
# resource "aws_elasticache_parameter_group" "valkey_default" {
#   name   = "miro-cache-${local.env.environment}-params"
#   family = "valkey7.2" # Adjust family based on chosen engine_version
#
#   parameter {
#     name  = "maxmemory-policy"
#     value = "allkeys-lru"
#   }
# }
