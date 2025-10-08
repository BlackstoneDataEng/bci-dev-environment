#!/bin/bash

# Script to build and push all Airflow images for version 0.0.10

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCKERFILE_PATH="$PROJECT_ROOT/bci-dev-environment/Dockerfile"
BUILD_CONTEXT="$PROJECT_ROOT"

REGISTRY="registryacr.azurecr.io"
NEW_VERSION="0.0.17"
TARGET_PLATFORM="linux/amd64"

# List of all images that need to be built
IMAGES=(
    "airflow-apiserver"
    "airflow-scheduler"
    "airflow-worker"
    "airflow-triggerer"
)

echo "=== Build and Push for All Airflow Images ==="
echo "Registry: $REGISTRY"
echo "Version: $NEW_VERSION"
echo "Platform: $TARGET_PLATFORM"
echo "Images: ${IMAGES[*]}"
echo

# Check if docker buildx is available
if ! docker buildx version &> /dev/null; then
    echo "❌ Docker Buildx is not available. Installing..."
    docker buildx install
fi

# Create builder if it does not exist
if ! docker buildx ls | grep -q "multiarch"; then
    echo "📦 Creating multi-architecture builder..."
    docker buildx create --name multiarch --use --bootstrap
else
    echo "📦 Using existing builder..."
    docker buildx use multiarch
fi

# Log in to ACR
echo "🔐 Logging in to Azure Container Registry..."
az acr login --name registryacr

# Build and push each image
for IMAGE_NAME in "${IMAGES[@]}"; do
    echo
    echo "🏗️  Building image: $IMAGE_NAME"
    echo "   Dockerfile: $DOCKERFILE_PATH"
    echo "   Context: $BUILD_CONTEXT"
    
    docker buildx build \
        --platform "$TARGET_PLATFORM" \
        --file "$DOCKERFILE_PATH" \
        --tag "$REGISTRY/$IMAGE_NAME:$NEW_VERSION" \
        --tag "$REGISTRY/$IMAGE_NAME:latest" \
        --push \
        "$BUILD_CONTEXT"
    
    echo "✅ Image $IMAGE_NAME built and pushed successfully!"
    echo "   $REGISTRY/$IMAGE_NAME:$NEW_VERSION"
done

echo
echo "🔍 Checking images in the registry..."
for IMAGE_NAME in "${IMAGES[@]}"; do
    echo "--- $IMAGE_NAME ---"
    az acr repository show-tags --name registryacr --repository $IMAGE_NAME --output table | head -10
done

echo
echo "=== Build for all images completed! ==="
echo "All images were updated to version $NEW_VERSION"
