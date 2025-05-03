# Configure Terragrunt to use S3 backend for remote state storage
remote_state {
  backend = "s3"
  config = {
    encrypt        = true
    bucket         = "miro-tfstate" 
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-west-1" 
    dynamodb_table = "miro-tfstate-lock-table" 
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}


skip_outputs_generation = true
