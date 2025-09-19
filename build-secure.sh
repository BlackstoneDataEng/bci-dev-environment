#!/bin/bash

# =============================================================================
# SECURE BUILD SCRIPT FOR DOCKERFILE_3
# Uses Docker BuildKit secrets to avoid embedding credentials in image layers
# =============================================================================

set -e

# Check if required environment variables are set
if [ -z "$AZURE_CLIENT_ID" ] || [ -z "$AZURE_CLIENT_SECRET" ] || [ -z "$AZURE_TENANT_ID" ]; then
    echo "Error: Azure credentials must be set as environment variables:"
    echo "  export AZURE_CLIENT_ID='your-client-id'"
    echo "  export AZURE_CLIENT_SECRET='your-client-secret'"
    echo "  export AZURE_TENANT_ID='your-tenant-id'"
    exit 1
fi

# Configuration
IMAGE_NAME="${IMAGE_NAME:-airflow-bci}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-your-registry.azurecr.io}"

echo "Building secure Airflow image..."
echo "Image: ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# Enable Docker BuildKit (required for secrets)
export DOCKER_BUILDKIT=1

# Create temporary files for secrets
TEMP_DIR=$(mktemp -d)
echo "$AZURE_CLIENT_ID" > "$TEMP_DIR/azure_client_id"
echo "$AZURE_CLIENT_SECRET" > "$TEMP_DIR/azure_client_secret"
echo "$AZURE_TENANT_ID" > "$TEMP_DIR/azure_tenant_id"

# Build with secrets (secrets are NOT stored in image layers)
docker build \
    --secret id=azure_client_id,src="$TEMP_DIR/azure_client_id" \
    --secret id=azure_client_secret,src="$TEMP_DIR/azure_client_secret" \
    --secret id=azure_tenant_id,src="$TEMP_DIR/azure_tenant_id" \
    --build-arg CACHE_BUST="$(date +%s)" \
    -f Dockerfile_3 \
    -t "${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}" \
    .

# Clean up temporary files
rm -rf "$TEMP_DIR"

echo "Build completed successfully!"
echo "Image: ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
echo ""
echo "To push to Azure Container Registry:"
echo "  az acr login --name $(echo $REGISTRY | cut -d'.' -f1)"
echo "  docker push ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
echo ""
echo "To verify no secrets are in the image:"
echo "  docker history ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
echo "  docker run --rm ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} find / -name '*azure*' -o -name '*ssh*' 2>/dev/null || true"