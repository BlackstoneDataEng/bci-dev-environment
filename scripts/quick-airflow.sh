#!/bin/bash

# Quick helper for Airflow port-forwarding
# Usage: ./scripts/quick-airflow.sh [local_port]

NAMESPACE="airflows"
LOCAL_PORT="${1:-5555}"
REMOTE_PORT="8080"

# Find the API server pod
APISERVER_POD=$(kubectl get pods -n "$NAMESPACE" -l app=airflow-apiserver -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$APISERVER_POD" ]; then
    echo "❌ airflow-apiserver pod not found"
    kubectl get pods -n "$NAMESPACE"
    exit 1
fi

echo "🚀 Connecting to Airflow..."
echo "Pod: $APISERVER_POD"
echo "URL: http://localhost:$LOCAL_PORT"
echo "User: admin"
echo ""
echo "To retrieve the password:"
echo "kubectl exec -ti $APISERVER_POD -n $NAMESPACE -- cat /opt/airflow/simple_auth_manager_passwords.json.generated"
echo ""
echo "Press Ctrl+C to stop"

kubectl port-forward "$APISERVER_POD" -n "$NAMESPACE" "$LOCAL_PORT:$REMOTE_PORT"
