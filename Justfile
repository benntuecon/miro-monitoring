# Variables
region := "us-west-1"
account_id := "398888507385"
registry := account_id + ".dkr.ecr." + region + ".amazonaws.com"
repository := "personal_project/miro"
function_name := "miro_monitoring"

# Get version from pyproject.toml
get-version:
    @uv run python -c "import sys; import tomllib; print(tomllib.load(sys.stdin.buffer)['project']['version'])" < pyproject.toml

# Build and push Docker image to ECR
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


