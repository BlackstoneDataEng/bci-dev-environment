#!/bin/bash

# Script to apply all updated Airflow deployments in Kubernetes

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NAMESPACE="airflows"
NEW_VERSION="11"

# Deployment manifest list
DEPLOYMENTS=(
    "$REPO_ROOT/deployment-airflow.yaml"
    "$REPO_ROOT/deployment-airflow-scheduler.yaml"
    "$REPO_ROOT/deployment-airflow-worker.yaml"
    "$REPO_ROOT/deployment-airflow-triggerer.yaml"
)

# Additional required resources
OTHER_RESOURCES=(
    "$REPO_ROOT/airflow-config.yaml"
    "$REPO_ROOT/airflow-service.yaml"
)

echo "=== Deploy All Airflow Services ==="
echo "Namespace: $NAMESPACE"
echo "Version: $NEW_VERSION"
echo

# Verify whether kubectl is configured
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ kubectl is not configured or the cluster is unavailable"
    exit 1
fi

# Check whether the namespace exists
if ! kubectl get namespace $NAMESPACE &> /dev/null; then
    echo "📦 Creating namespace $NAMESPACE..."
    kubectl create namespace $NAMESPACE
else
    echo "✅ Namespace $NAMESPACE already exists"
fi

# Apply configuration resources first
echo
echo "🔧 Applying configuration resources..."
for RESOURCE in "${OTHER_RESOURCES[@]}"; do
    if [ -f "$RESOURCE" ]; then
        echo "   Applying: $(basename $RESOURCE)"
        kubectl apply -f "$RESOURCE" -n $NAMESPACE
    else
        echo "   ⚠️  File not found: $RESOURCE"
    fi
done

# Apply deployments
echo
echo "🚀 Applying deployments..."
for DEPLOYMENT in "${DEPLOYMENTS[@]}"; do
    if [ -f "$DEPLOYMENT" ]; then
        echo "   Applying: $(basename $DEPLOYMENT)"
        kubectl apply -f "$DEPLOYMENT" -n $NAMESPACE
    else
        echo "   ⚠️  File not found: $DEPLOYMENT"
    fi
done

# Wait for deployment rollouts
echo
echo "⏳ Waiting for deployment rollouts..."
DEPLOYMENT_NAMES=(
    "airflow-apiserver"
    "airflow-scheduler"
    "airflow-worker"
    "airflow-triggerer"
)

for DEPLOYMENT_NAME in "${DEPLOYMENT_NAMES[@]}"; do
    echo "   Waiting: $DEPLOYMENT_NAME"
    kubectl rollout status deployment/$DEPLOYMENT_NAME -n $NAMESPACE --timeout=300s
done

# Show pod status
echo
echo "📊 Pod status:"
kubectl get pods -n $NAMESPACE -o wide

# Check deployment image versions
echo
echo "🔍 Checking deployment image versions:"
for DEPLOYMENT_NAME in "${DEPLOYMENT_NAMES[@]}"; do
    IMAGE=$(kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}')
    echo "   $DEPLOYMENT_NAME: $IMAGE"
done

# Check services
echo
echo "🌐 Available services:"
kubectl get services -n $NAMESPACE

echo
echo "=== Deploy completed! ==="
echo "All services were updated to version $NEW_VERSION"
echo
echo "To access the Airflow Web UI:"
echo "  kubectl port-forward svc/airflow-apiserver-service 8080:8080 -n $NAMESPACE"
echo "  Then open: http://localhost:8080"
