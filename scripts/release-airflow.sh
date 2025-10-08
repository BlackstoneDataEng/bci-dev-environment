#!/bin/bash

set -euo pipefail

SCRIPT_NAME=$(basename "$0")

usage() {
  cat <<USAGE
Usage: $SCRIPT_NAME <version>

Builds and pushes Airflow component images for the specified version, then
deploys them to the configured Kubernetes namespace (default: airflows).

Environment overrides:
  REGISTRY        Container registry (default: registryacr.azurecr.io)
  TARGET_PLATFORM Build platform for docker buildx (default: linux/amd64)
  BUILDER_NAME    Name for docker buildx builder (default: multiarch)
  NAMESPACE       Kubernetes namespace (default: airflows)
  CONFIG_ONLY     If set to "true", skip build/push and only apply manifests
USAGE
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

VERSION="$1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$REPO_ROOT/.." && pwd)"
DOCKERFILE_PATH="$REPO_ROOT/Dockerfile"
BUILD_CONTEXT="$PROJECT_ROOT"

REGISTRY="${REGISTRY:-registryacr.azurecr.io}"
TARGET_PLATFORM="${TARGET_PLATFORM:-linux/amd64}"
BUILDER_NAME="${BUILDER_NAME:-multiarch}"
NAMESPACE="${NAMESPACE:-airflows}"
CONFIG_ONLY="${CONFIG_ONLY:-false}"

IMAGES=(
  "airflow-apiserver"
  "airflow-scheduler"
  "airflow-worker"
  "airflow-triggerer"
)

CONFIG_RESOURCES=(
  "$REPO_ROOT/airflow-config.yaml"
  "$REPO_ROOT/airflow-service.yaml"
  "$REPO_ROOT/airflow-pvc.yaml"
)

DEPLOYMENT_RESOURCES=(
  "$REPO_ROOT/deployment-airflow.yaml"
  "$REPO_ROOT/deployment-airflow-scheduler.yaml"
  "$REPO_ROOT/deployment-airflow-worker.yaml"
  "$REPO_ROOT/deployment-airflow-triggerer.yaml"
)

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

info() {
  echo "[$(timestamp)] $1"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: '$1' is required but not installed." >&2
    exit 1
  fi
}

confirm() {
  local prompt="$1"
  read -r -p "$prompt (y/N): " reply
  [[ $reply =~ ^[Yy]$ ]]
}

ensure_buildx() {
  if ! docker buildx version >/dev/null 2>&1; then
    info "Docker Buildx not found. Installing..."
    docker buildx install
  fi

  if docker buildx inspect "$BUILDER_NAME" >/dev/null 2>&1; then
    info "Using existing buildx builder '$BUILDER_NAME'."
    docker buildx use "$BUILDER_NAME"
    docker buildx inspect "$BUILDER_NAME" --bootstrap >/dev/null 2>&1 || true
  else
    info "Creating buildx builder '$BUILDER_NAME'..."
    docker buildx create --name "$BUILDER_NAME" --use --bootstrap
  fi
}

build_and_push_images() {
  info "Authenticating with Azure Container Registry '$REGISTRY'..."
  az acr login --name "${REGISTRY%%.*}"

  info "Building and pushing images for version $VERSION..."
  for image in "${IMAGES[@]}"; do
    info "Building ${image}:${VERSION}"
    docker buildx build \
      --platform "$TARGET_PLATFORM" \
      --file "$DOCKERFILE_PATH" \
      --tag "$REGISTRY/$image:$VERSION" \
      --tag "$REGISTRY/$image:latest" \
      --push \
      "$BUILD_CONTEXT"
  done

  info "Image build and push complete."
}

ensure_cluster_ready() {
  info "Validating kubectl access..."
  if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "Error: Unable to reach Kubernetes cluster with current kubectl context." >&2
    exit 1
  fi

  if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    info "Creating namespace '$NAMESPACE'..."
    kubectl create namespace "$NAMESPACE"
  else
    info "Namespace '$NAMESPACE' already exists."
  fi
}

apply_kubernetes_resources() {
  info "Applying configuration resources..."
  for resource in "${CONFIG_RESOURCES[@]}"; do
    if [[ -f "$resource" ]]; then
      info "kubectl apply -f $(basename "$resource")"
      kubectl apply -f "$resource" -n "$NAMESPACE"
    else
      echo "Warning: Configuration file '$resource' not found." >&2
    fi
  done

  info "Applying deployment manifests..."
  for deployment in "${DEPLOYMENT_RESOURCES[@]}"; do
    if [[ -f "$deployment" ]]; then
      info "kubectl apply -f $(basename "$deployment")"
      kubectl apply -f "$deployment" -n "$NAMESPACE"
    else
      echo "Warning: Deployment file '$deployment' not found." >&2
    fi
  done
}

update_deployment_images() {
  info "Updating deployment images to version $VERSION..."
  for image in "${IMAGES[@]}"; do
    info "Setting image for deployment/$image"
    kubectl set image "deployment/$image" \
      "$image=$REGISTRY/$image:$VERSION" \
      -n "$NAMESPACE" \
      --record
  done
}

wait_for_rollouts() {
  info "Waiting for deployment rollouts..."
  for image in "${IMAGES[@]}"; do
    kubectl rollout status "deployment/$image" -n "$NAMESPACE" --timeout=300s
  done
}

show_summary() {
  info "Deployment summary:"
  kubectl get deployments -n "$NAMESPACE"
  kubectl get pods -n "$NAMESPACE" -o wide

  info "Current container images:"
  kubectl get deployments -n "$NAMESPACE" \
    -o jsonpath='{range .items[*]}{.metadata.name}{" => "}{.spec.template.spec.containers[0].image}{"\n"}{end}'
}

# --- main flow ---

require_command docker
require_command az
require_command kubectl

if [[ ! -f "$DOCKERFILE_PATH" ]]; then
  echo "Error: Dockerfile not found at $DOCKERFILE_PATH" >&2
  exit 1
fi

info "Preparing Airflow release"
echo "  Version:   $VERSION"
echo "  Registry:  $REGISTRY"
echo "  Namespace: $NAMESPACE"
echo "  Platform:  $TARGET_PLATFORM"
echo

if ! confirm "Continue with build and deploy"; then
  echo "Operation cancelled."
  exit 0
fi

if [[ "$CONFIG_ONLY" != "true" ]]; then
  ensure_buildx
  build_and_push_images
else
  info "CONFIG_ONLY=true detected. Skipping build and push phase."
fi

ensure_cluster_ready
apply_kubernetes_resources

if [[ "$CONFIG_ONLY" != "true" ]]; then
  update_deployment_images
fi

wait_for_rollouts
show_summary

info "Release workflow completed successfully."
echo "Access the Airflow UI via port-forward or exposed service as documented."
