# Variables
region := "us-west-1"
account_id := "398888507385"
registry := account_id + ".dkr.ecr." + region + ".amazonaws.com"
repository := "personal_project/miro"
function_name := "miro_monitoring"

# Get version from pyproject.toml using uv
get-version:
    @uv run python -c "import sys; import tomllib; print(tomllib.load(sys.stdin.buffer)['project']['version'])" < pyproject.toml

# Build and push Docker image to ECR (without Lambda deployment)
build:
    #!/usr/bin/env bash
    set -e
    VERSION=$(just get-version)
    echo "Logging in to ECR..."
    aws ecr get-login-password --region {{region}} | docker login --username AWS --password-stdin {{registry}}

    echo "Building Docker image version: $VERSION..."
    docker buildx build -f "Dockerfile" \
        --platform=linux/amd64 \
        --tag {{registry}}/{{repository}}:$VERSION \
        --build-arg BUILD_VERSION=$VERSION \
        --provenance=false \
        --output type=image,push=true,oci-mediatypes=false,compression=gzip,compression-level=9,force-compression=true .
    echo "Image built and pushed: {{registry}}/{{repository}}:$VERSION"

# Infrastructure Management (Terragrunt)

# Initialize all modules
infra-init:
    @echo "Initializing Terragrunt modules in dev environment..."
    @cd terraform/dev && terragrunt run-all init

# Initialize specific module
infra-init-module module:
    @echo "Initializing {{module}} module in dev environment..."
    @cd terraform/dev/{{module}} && terragrunt init

# Apply all infrastructure
infra-apply:
    #!/usr/bin/env bash
    set -e
    VERSION=$(just get-version)
    echo "Applying Terragrunt configuration with Lambda image version: $VERSION"
    cd terraform/dev && TF_VAR_lambda_image_tag=$VERSION terragrunt run-all apply

# Apply specific module
infra-apply-module module:
    #!/usr/bin/env bash
    set -e
    if [ "{{module}}" = "lambda" ]; then
        VERSION=$(just get-version)
        echo "Applying {{module}} module with image version: $VERSION"
        cd terraform/dev/{{module}} && TF_VAR_lambda_image_tag=$VERSION terragrunt apply
    else
        echo "Applying {{module}} module..."
        cd terraform/dev/{{module}} && terragrunt apply
    fi

# Apply specific module non-interactively
infra-apply-module-auto module:
    #!/usr/bin/env bash
    set -e
    if [ "{{module}}" = "lambda" ]; then
        VERSION=$(just get-version)
        echo "Applying {{module}} module with image version: $VERSION (auto-approve)"
        cd terraform/dev/{{module}} && TF_VAR_lambda_image_tag=$VERSION terragrunt apply -auto-approve
    else
        echo "Applying {{module}} module (auto-approve)..."
        cd terraform/dev/{{module}} && terragrunt apply -auto-approve
    fi

# Deploy only Lambda with the current version after building
deploy-lambda:
    #!/usr/bin/env bash
    set -e
    VERSION=$(just get-version)
    echo "Deploying Lambda with image version: $VERSION"
    cd terraform/dev/lambda && TF_VAR_lambda_image_tag=$VERSION terragrunt apply

# Build and deploy in one command
build-and-deploy: build deploy-lambda

# Destroy infrastructure
infra-destroy:
    @echo "Destroying Terragrunt-managed infrastructure in dev environment..."
    @echo "You will be prompted to confirm the destruction."
    @cd terraform/dev && terragrunt run-all destroy

# Plan changes (without applying)
infra-plan:
    #!/usr/bin/env bash
    set -e
    VERSION=$(just get-version)
    echo "Planning infrastructure changes with Lambda image version: $VERSION"
    cd terraform/dev && TF_VAR_lambda_image_tag=$VERSION terragrunt run-all plan

# Plan changes for specific module
infra-plan-module module:
    #!/usr/bin/env bash
    set -e
    if [ "{{module}}" = "lambda" ]; then
        VERSION=$(just get-version)
        echo "Planning {{module}} module changes with image version: $VERSION"
        cd terraform/dev/{{module}} && TF_VAR_lambda_image_tag=$VERSION terragrunt plan
    else
        echo "Planning {{module}} module changes..."
        cd terraform/dev/{{module}} && terragrunt plan
    fi

# Output from specific module
infra-output module:
    @echo "Getting outputs from {{module}} module..."
    @cd terraform/dev/{{module}} && terragrunt output

# Bump version using cz
bump type="":
    @echo "Bumping version..."
    @uv run cz bump {{type}}

# Create a conventional commit using cz
commit:
    @uv run cz commit

# Show current version
version:
    @echo "Current version: $(just get-version)"
