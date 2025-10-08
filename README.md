# BCI Airflow Deployment Environment

## Overview
This repository provides a complete development and deployment toolkit for the BCI Airflow stack. It contains:

- A custom Airflow Docker image with Spark support, Azure connectors, and repository-specific Python packages.
- A Docker Compose stack for local development that provisions Airflow (Celery executor), PostgreSQL, Redis, Spark, and Azurite for Azure Storage emulation.
- A collection of Kubernetes manifests designed for Azure Kubernetes Service (AKS), including workload identity integration and persistent storage.
- Automation scripts that simplify image builds, environment upgrades, and cluster rollouts.

Use this project to iterate locally, generate release images, and apply the same configuration to Kubernetes with minimal drift.

## Repository Structure
- `Dockerfile` – Builds the Airflow base image with Java, Python dependencies, and project DAGs/plugins.
- `docker-compose.yml` – Local stack definition for Airflow core services, Spark helpers, PostgreSQL, Redis, and Azurite.
- `requirements.txt` – Python dependencies baked into the custom Airflow image.
- `config/airflow.cfg` – Local Airflow configuration consumed by Docker Compose.
- `airflow-config.yaml` – Kubernetes ConfigMap that mirrors key Airflow configuration entries.
- `airflow-service.yaml` – ClusterIP service that exposes the Airflow API server internally.
- `deployment-airflow*.yaml` – Deployment manifests for API server, scheduler, worker, and triggerer components.
- `airflow-pvc.yaml` – PersistentVolumeClaim for shared Airflow logs in Kubernetes.
- `azure-files-sc.yaml` – Azure Files StorageClass definition used by the PVC.
- `scripts/` – Automation utilities for building images, deploying to AKS, and connecting to running clusters.
- `.env.example` – Template for environment variables used by Docker Compose and scripts.
- `data/`, `logs/` – Local bind mounts used by the Docker Compose stack for persistence.

## Prerequisites

### Local Development
- Docker Engine 24+ with the Compose plugin.
- `docker buildx` (installed automatically by the scripts if missing).
- Optional: `az` CLI and `kubectl` if you want to use the helper scripts that interact with AKS from your workstation.

### Kubernetes Deployment
- An AKS cluster with Azure Workload Identity configured.
- Azure Key Vault containing the Airflow connection and variable secrets referenced in `airflow-config.yaml`.
- `kubectl`, `az` CLI, and appropriate access to the target subscription/resource group.
- Kubernetes secrets named `airflow-db-secret`, `airflow-broker-secret`, and `airflow-secrets` populated in the `airflows` namespace.

## Configuration
1. Duplicate `.env.example` to `.env` and set values for Azure credentials, TrackTik API access, PostgreSQL, and Airflow admin credentials. The Docker Compose file and helper scripts automatically load these variables.
2. Adjust `config/airflow.cfg` for local behavior. For Kubernetes, edit `airflow-config.yaml` (ConfigMap) as needed.
3. Update `requirements.txt` when new Python dependencies are required. Rebuild the Docker image to propagate changes.
4. DAGs should be stored in `bci-dags/` and plugins in `bci-datamart/` at the repository root so that the Docker build context copies them into the image.

## Running Airflow Locally (Docker Compose)
1. Build the image and initialize metadata: `docker compose up airflow-init`.
2. Start the full stack: `docker compose up -d`.
3. Access the Airflow UI at `http://localhost:8080` (default credentials come from `_AIRFLOW_WWW_USER_USERNAME` / `_AIRFLOW_WWW_USER_PASSWORD`).
4. Logs are written to `logs/`, DAG data to `data/`, and configuration overrides to `config/`.
5. Stop services with `docker compose down` or remove volumes with `docker compose down --volumes`.

Optional services:
- Spark master UI: `http://localhost:8083`
- Spark worker UI: `http://localhost:8081`
- Azurite endpoints: Blob (`http://localhost:10000`), Queue (`http://localhost:10001`), Table (`http://localhost:10002`)

## Building and Publishing Container Images
- `scripts/release-airflow.sh <version>` is the primary release command. It builds and pushes all Airflow images for the provided version, applies Kubernetes manifests, updates deployment image tags, and waits for successful rollouts. Example:
  ```bash
  ./scripts/release-airflow.sh 0.0.18
  ```
  Set `CONFIG_ONLY=true` to apply manifests without rebuilding images.
- `scripts/build-all-images.sh` remains available for manual or CI-driven image builds when you do not need to trigger a deployment.

## Kubernetes Deployment
1. Authenticate to Azure and set the AKS context:
   ```bash
   az login
   az aks get-credentials --resource-group <rg> --name <cluster>
   ```
2. (Optional) Create the storage class if it does not exist:
   ```bash
   kubectl apply -f azure-files-sc.yaml
   ```
3. Apply shared resources:
   ```bash
   kubectl apply -f airflow-config.yaml
   kubectl apply -f airflow-service.yaml
   kubectl apply -f airflow-pvc.yaml
   ```
4. Deploy workloads:
   ```bash
   kubectl apply -f deployment-airflow.yaml
   kubectl apply -f deployment-airflow-scheduler.yaml
   kubectl apply -f deployment-airflow-worker.yaml
   kubectl apply -f deployment-airflow-triggerer.yaml
   ```
5. Monitor rollouts:
   ```bash
   kubectl rollout status deployment/airflow-apiserver -n airflows
   kubectl get pods -n airflows -o wide
   ```

The `scripts/deploy-all-services.sh` script automates the sequence above, including namespace creation and post-deploy checks. Customize the namespace and version variables in the script when needed.

## Helper Scripts
- `scripts/connect-airflow-ui.sh` – End-to-end helper that obtains cluster credentials, finds the API server pod, and enables port-forwarding to the Airflow UI.
- `scripts/quick-airflow.sh` – Lightweight port-forward utility when you already have cluster access.
- `scripts/build-all-images.sh` – Builds/pushes Airflow images for a specified version.
- `scripts/deploy-all-services.sh` – Applies configuration resources, deployments, and waits for rollouts in AKS.
- `scripts/release-airflow.sh` – Comprehensive release workflow covering build, push, deploy, and rollout verification.

Refer to `scripts/README.md` for more detailed usage notes and troubleshooting commands.

## Operations and Maintenance
- **Logs:** Local logs live in `logs/`; Kubernetes pods stream worker logs via the log server port (`8793`).
- **Secrets:** Airflow relies on Azure Key Vault via the `AzureKeyVaultBackend`. Ensure required secrets exist before deploying.
- **Dependencies:** Update `requirements.txt` and rebuild the image to propagate new Python packages. Keep the Spark JAR versions in the Dockerfile aligned with your cluster requirements.
- **Scaling:** Adjust replica counts directly in the Kubernetes deployment manifests. For local Docker Compose testing, tune resource limits using Docker Desktop or the Compose file.
- **Housekeeping:** Use `docker compose down --volumes --remove-orphans` to reset the local environment. For AKS, clean up with `kubectl delete -f <manifest>` when resources are no longer required.

## Troubleshooting
- Use `docker compose logs <service>` to inspect local containers, or `kubectl logs` / `kubectl describe` for Kubernetes workloads.
- Verify that the Kubernetes secrets and ConfigMaps exist before redeploying pods.
- When upgrading, monitor `scripts/release-airflow.sh` output—any failure in image builds or rollouts will abort the process early for easier debugging.