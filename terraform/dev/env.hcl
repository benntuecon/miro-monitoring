locals {
  # Environment specific configuration
  aws_region = "us-west-1"
  account_id = "398888507385"
  environment = "dev"

  # Common tags to apply to all resources
  tags = {
    environment = local.environment
    project     = "miro"
    managed_by  = "terragrunt"
  }

  # VPC Configuration
  vpc_cidr = "10.0.0.0/16"
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  # Cache Configuration
  cache_node_type = "cache.t3.micro" # Choose an appropriate instance type

  # Lambda Configuration
  lambda_function_name = "miro_monitoring"
  # Get the image tag from environment variable or default to "latest"
  lambda_image_tag     = get_env("TF_VAR_lambda_image_tag", "latest")
  lambda_ecr_repo_name = "personal_project/miro"

} 