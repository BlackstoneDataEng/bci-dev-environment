# Airflow Scripts

Scripts that simplify accessing and managing Airflow in AKS.

## 🚀 Available Scripts

### 1. `connect-airflow-ui.sh` – Full Workflow
A complete script that automates the entire connection process to the Airflow UI.

**Features:**
- ✅ Checks dependencies (`az`, `kubectl`)
- 🔐 Logs in to Azure if needed
- 🔑 Retrieves AKS credentials automatically
- 📦 Lists pods and locates the API server
- 🔐 Retrieves the Airflow password automatically
- 🌐 Starts port-forwarding with automatic cleanup
- 🌐 Opens the browser automatically (macOS)

**Usage:**
```bash
./scripts/connect-airflow-ui.sh
```

### 2. `quick-airflow.sh` – Quick Script
A lightweight port-forward helper when you are already connected to the cluster.

### 3. `release-airflow.sh` – Full Release Pipeline
Single entry point to build/push all Airflow container images for a specific version, apply Kubernetes manifests, update deployment image tags, and verify rollouts. The version is required:

```bash
./scripts/release-airflow.sh 0.0.18

# Only apply manifests (no build/push)
CONFIG_ONLY=true ./scripts/release-airflow.sh 0.0.18
```

**Usage:**
```bash
# Default port 5555
./scripts/quick-airflow.sh

# Custom port
./scripts/quick-airflow.sh 8080
```

## 📋 Manual Commands (Cheat Sheet)

### Login and Credentials
```bash
# Azure login
az login

# Retrieve AKS credentials
az aks get-credentials --resource-group datawarehouse-rg --name aks-datawarehouse
```

### Pod Management
```bash
# List pods
kubectl get pod -n airflows

# Apply deployment
kubectl apply -f deployment-airflow.yaml -n airflows

# Delete deployment
kubectl delete deploy airflow-apiserver -n airflows

# Redeploy
kubectl apply -f deployment-airflow.yaml -n airflows
```

### Manual Port Forward
```bash
# Locate pod
POD_NAME=$(kubectl get pods -n airflows -l app=airflow-apiserver -o jsonpath='{.items[0].metadata.name}')

# Port forward
kubectl port-forward $POD_NAME -n airflows 5555:8080
```

### Retrieve Password
```bash
# Exec into pod
kubectl exec -ti <pod_name> -n airflows -- /bin/bash

# Get password
kubectl exec -ti <pod_name> -n airflows -- cat /opt/airflow/simple_auth_manager_passwords.json.generated
```

## 🌐 UI Access

After running any port-forward script:

- **URL:** http://localhost:5555 (or chosen port)
- **User:** admin
- **Password:** Retrieved automatically by the script or manually

## 🔧 Troubleshooting

### Port in Use
```bash
# Check process using the port
lsof -i :5555

# Kill process
lsof -ti:5555 | xargs kill -9
```

### Pod Not Found
```bash
# Check pod status
kubectl get pods -n airflows

# Check logs
kubectl logs -l app=airflow-apiserver -n airflows
```

### Connectivity Issues
```bash
# Confirm the correct context
kubectl config current-context

# Confirm the namespace exists
kubectl get namespaces | grep airflows
```
