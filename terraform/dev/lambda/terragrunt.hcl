include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "terraform-aws-modules/lambda/aws//."
  # Pin to a specific version for production stability. Find latest: https://registry.terraform.io/modules/terraform-aws-modules/lambda/aws/latest
  version = "~> 7.3" 
}

# Define dependencies on other modules
dependency "vpc" {
  config_path = "../vpc"
  # Mock outputs for plan/validate when VPC isn't deployed yet
  mock_outputs = {
    vpc_id             = "vpc-1234567890abcdef0"
    private_subnets    = ["subnet-123", "subnet-456"] # Used by lambda_sg
    private_subnet_ids = ["subnet-123", "subnet-456"] # Used by lambda module
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "cache" {
  config_path = "../cache"
  # Mock outputs for plan/validate when Cache isn't deployed yet
  mock_outputs = {
    elasticache_cluster_address = ["miro-cache-dev.mock.cache.amazonaws.com"]
    # Use the primary_endpoint_address if available in the cache module's outputs
    # elasticache_primary_endpoint_address = "miro-cache-dev.mock.cache.amazonaws.com" 
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

# --- Inputs for the Lambda Module ---
inputs = {
  function_name = local.env.lambda_function_name
  description   = "MiRO Monitoring Lambda function using container image"
  # Handler and runtime are not needed for image-based Lambdas but the module requires a placeholder
  handler       = "not.required"
  runtime       = "nodejs18.x" # Placeholder, ignored for Image package_type
  architectures = ["x86_64"]   # Should match the architecture of your Docker image

  # Container Image Configuration
  create_package = false
  package_type   = "Image"
  image_uri      = "${local.env.account_id}.dkr.ecr.${local.env.aws_region}.amazonaws.com/${local.env.lambda_ecr_repo_name}:${local.env.lambda_image_tag}" # Image URI construction
  # IMPORTANT: Ensure local.env.lambda_image_tag is updated before apply (e.g., via env var or tfvars)

  # VPC Configuration
  vpc_subnet_ids         = dependency.vpc.outputs.private_subnet_ids
  vpc_security_group_ids = [aws_security_group.lambda_sg.id] # Attach the SG defined below
  attach_vpc_policy      = true # Attach the AWS managed policy for VPC access (ENI creation etc.)

  # Environment Variables
  environment_variables = {
    # Use the correct output from the cache module. Adjust if using cluster mode or different output name.
    VALKEY_HOST = one(dependency.cache.outputs.elasticache_cluster_address) # Get the single endpoint address
    VALKEY_PORT = "6379" # Default Valkey port
    AWS_REGION  = local.env.aws_region
    # Add any other environment variables your Lambda function needs
  }

  # IAM Role & Policies
  create_role           = true
  attach_basic_policy   = true # AWSLambdaBasicExecutionRole
  attach_network_policy = true # AWSLambdaVPCAccessExecutionRole
  # Attach custom policy for ElastiCache access defined below
  policies = [
    aws_iam_policy.lambda_elasticache_policy.arn
  ]
  # You can add more policies here if needed

  # Lambda Function Settings
  timeout     = 60  # Seconds
  memory_size = 512 # MB

  # Tags
  tags = merge(
    local.env.tags,
    {
      "Name" = "${local.env.lambda_function_name}-${local.env.environment}"
    }
  )
}

# --- Supporting Resources Defined in this Terragrunt File ---

# Security Group for the Lambda Function
resource "aws_security_group" "lambda_sg" {
  name        = "${local.env.lambda_function_name}-${local.env.environment}-sg"
  description = "Allow Lambda egress and communication with Valkey Cache"
  vpc_id      = dependency.vpc.outputs.vpc_id

  # Allow all egress traffic (typical for Lambdas needing internet or AWS service access)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # No ingress rules needed here usually, unless something needs to trigger the Lambda via its ENI IP.
  # Access to the cache is handled via the cache's security group ingress rules.

  tags = merge(
    local.env.tags,
    {
      "Name" = "${local.env.lambda_function_name}-${local.env.environment}-sg"
    }
  )
}

# IAM Policy for Lambda to Access ElastiCache (Valkey)
resource "aws_iam_policy" "lambda_elasticache_policy" {
  name        = "${local.env.lambda_function_name}-${local.env.environment}-elasticache-access"
  description = "IAM policy allowing Lambda to describe ElastiCache resources"
  # Policy providing minimal necessary permissions. Adjust if data plane actions via IAM are needed.
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "elasticache:DescribeCacheClusters",
          "elasticache:DescribeReplicationGroups",
          "elasticache:ListTagsForResource"
          # Generally, data access is controlled by Security Groups, not IAM for ElastiCache.
        ],
        Resource = "*" # Consider scoping this down to the specific cluster ARN if known/static
      },
    ]
  })

  tags = merge(
    local.env.tags,
    {
      "Name" = "${local.env.lambda_function_name}-${local.env.environment}-elasticache-access"
    }
  )
}

# --- Outputs from this Module ---

# Output the Lambda function's security group ID so it can be used by other modules (like the cache SG)
output "lambda_security_group_id" {
  value       = aws_security_group.lambda_sg.id
  description = "The ID of the security group attached to the Lambda function"
}

output "lambda_function_arn" {
  value       = module.lambda.lambda_function_arn
  description = "The ARN of the Lambda function"
}

# Expose locals from the included env.hcl file for use in this file
locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
} 