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

PASSWORD_JSON=$(kubectl exec -n "$NAMESPACE" "$APISERVER_POD" -- cat /opt/airflow/simple_auth_manager_passwords.json.generated 2>/dev/null)

if [ -z "$PASSWORD_JSON" ]; then
    echo "⚠️ Unable to retrieve password automatically."
    echo "   Try: kubectl exec -ti $APISERVER_POD -n $NAMESPACE -- cat /opt/airflow/simple_auth_manager_passwords.json.generated"
else
    PYTHON_CMD=$(command -v python3 || command -v python)
    if [ -z "$PYTHON_CMD" ]; then
        echo "⚠️ Python not available locally to parse password."
        echo "   Raw JSON:"
        echo "$PASSWORD_JSON"
    else
        PASSWORD=$(printf '%s' "$PASSWORD_JSON" | "$PYTHON_CMD" -c 'import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)

password = None
if isinstance(data, dict):
    password = data.get("admin")
    if password is None and len(data) == 1:
        password = next(iter(data.values()))

if not password:
    sys.exit(2)

sys.stdout.write(password)')
        PARSE_STATUS=$?
        if [ "$PARSE_STATUS" -eq 0 ] && [ -n "$PASSWORD" ]; then
            echo "Password: $PASSWORD"
        else
            echo "⚠️ Unable to parse password from JSON."
            echo "   Raw JSON:"
            echo "$PASSWORD_JSON"
        fi
    fi
fi

echo ""
echo "Press Ctrl+C to stop"

kubectl port-forward "$APISERVER_POD" -n "$NAMESPACE" "$LOCAL_PORT:$REMOTE_PORT"
