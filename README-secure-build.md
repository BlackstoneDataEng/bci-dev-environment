# Secure Airflow Docker Build

This directory contains a secure, production-ready Dockerfile for building Airflow images with pre-loaded DAGs and plugins from private GitHub repositories.

## Security Features

✅ **Multi-stage build** - Secrets only exist in build stage, not final image  
✅ **Docker BuildKit secrets** - Credentials never stored in image layers  
✅ **Azure Key Vault integration** - SSH keys fetched securely at build time  
✅ **Clean final image** - No traces of credentials or temporary files  

## Files

- `Dockerfile_3` - Secure multi-stage production Dockerfile
- `build-secure.sh` - Secure build script using BuildKit secrets
- `docker-compose.yml` - Development environment with mounted volumes

## Usage

### 1. Set Azure Credentials

```bash
export AZURE_CLIENT_ID="your-service-principal-client-id"
export AZURE_CLIENT_SECRET="your-service-principal-secret"
export AZURE_TENANT_ID="your-azure-tenant-id"
```

### 2. Build Securely

```bash
# Using the provided script (recommended)
./build-secure.sh

# Or manually with custom settings
export IMAGE_NAME="airflow-bci"
export IMAGE_TAG="v1.0.0"
export REGISTRY="myregistry.azurecr.io"
./build-secure.sh
```

### 3. Deploy to Azure Container Registry

```bash
# Login to your registry
az acr login --name myregistry

# Push the image
docker push myregistry.azurecr.io/airflow-bci:v1.0.0
```

## Security Verification

To verify no secrets are embedded in the final image:

```bash
# Check image history for any secret references
docker history myregistry.azurecr.io/airflow-bci:v1.0.0

# Search for any leftover credential files
docker run --rm myregistry.azurecr.io/airflow-bci:v1.0.0 \
  find / -name '*azure*' -o -name '*ssh*' 2>/dev/null || echo "No credential files found"
```

## How It Works

### Build Stage (Discarded)
1. Installs Azure CLI and Git tools
2. Uses BuildKit secrets to access Azure credentials
3. Fetches SSH keys from Azure Key Vault
4. Clones private repositories using SSH
5. Copies repositories to standard locations
6. **All secrets and temporary files are cleaned up**

### Production Stage (Final Image)
1. Starts fresh from base Airflow image
2. Installs Java and production dependencies
3. **Copies only the repositories** from build stage
4. No secrets, credentials, or temporary files
5. Ready for production deployment

## Development vs Production

- **Development**: Use `docker-compose.yml` with mounted volumes
- **Production**: Use `Dockerfile_3` with baked-in repositories

## Prerequisites

- Docker with BuildKit enabled
- Azure CLI access to Key Vault `bci-keyss`
- Service principal with Key Vault secret read permissions
- SSH keys stored as secrets: `bci-git-key`, `bci-git-keys-dags`

## Troubleshooting

If build fails:
1. Verify Azure credentials are correct
2. Check Key Vault permissions
3. Ensure SSH keys are valid in Azure Key Vault
4. Enable BuildKit: `export DOCKER_BUILDKIT=1`