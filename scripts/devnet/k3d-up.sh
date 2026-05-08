#!/usr/bin/env bash
# Single-command bring-up for the full-stack k3d devnet.
#
# Canonical: docs/technical/full-stack-devnet.md §"k3d single-command bring-up"
# Issue:     #146.
#
# Steps:
#   1. Create (or reuse) a k3d cluster with the same host port surface as
#      docker-compose.full-stack.yaml (8545/5432/8080/5173).
#   2. Build the four custom images (explorer-indexer, explorer-api, dapp,
#      gateway-deployer) and `k3d image import` them.
#   3. Apply the kustomize tree at deploy/k3d/, overriding the fork-rpc
#      Secret with the values from the environment (RMPC_FORK_RPC_URL,
#      RMPC_FORK_BLOCK).
#   4. Wait for the gateway-deployer Job to complete; copy the deployment
#      JSON out via `kubectl cp` and re-apply it as a ConfigMap so the
#      indexer can read it.
#   5. Roll out the indexer Deployment now that the artifact is present.
#   6. Poll `explorer-api /health` from the host until 200.
#
# Required env:
#   RMPC_FORK_RPC_URL    archive RPC for `anvil --fork-url`
#
# Optional env (with defaults):
#   RMPC_FORK_BLOCK      pinned block (default 29800000)
#   K3D_CLUSTER_NAME     cluster name (default rm-devnet)
#   POSTGRES_PASSWORD    devnet password (default rmoney_dev)
#
# Idempotent: re-running reuses an existing cluster, re-imports images,
# and re-applies manifests.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

CLUSTER_NAME="${K3D_CLUSTER_NAME:-rm-devnet}"
RMPC_FORK_BLOCK="${RMPC_FORK_BLOCK:-29800000}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-rmoney_dev}"

if [ -z "${RMPC_FORK_RPC_URL:-}" ]; then
  echo "ERROR: RMPC_FORK_RPC_URL must be set (archive RPC for anvil --fork-url)" >&2
  exit 1
fi

for tool in k3d kubectl docker; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: required tool '$tool' not on PATH" >&2
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# 1. Cluster.
# ---------------------------------------------------------------------------
if k3d cluster list --no-headers 2>/dev/null | awk '{print $1}' | grep -qx "$CLUSTER_NAME"; then
  echo "[k3d-up] reusing existing cluster '$CLUSTER_NAME'"
else
  echo "[k3d-up] creating cluster '$CLUSTER_NAME'"
  # Publish the four host ports through klipper-lb (k3d serverlb).
  k3d cluster create "$CLUSTER_NAME" \
    --port "8545:8545@loadbalancer" \
    --port "5432:5432@loadbalancer" \
    --port "8080:8080@loadbalancer" \
    --port "5173:5173@loadbalancer" \
    --wait \
    --timeout 120s
fi

kubectl config use-context "k3d-${CLUSTER_NAME}" >/dev/null

# ---------------------------------------------------------------------------
# 2. Build + import images.
# ---------------------------------------------------------------------------
echo "[k3d-up] building images"
docker build --tag rm-explorer-indexer:k3d --file services/explorer-indexer/Dockerfile .
docker build --tag rm-explorer-api:k3d     --file clients/explorer-api/Dockerfile     .
docker build --tag rm-dapp:k3d             --file clients/dapp/Dockerfile             .
docker build --tag rm-gateway-deployer:k3d --file deploy/k3d/Dockerfile.gateway-deployer .

echo "[k3d-up] importing images into k3d"
k3d image import \
  rm-explorer-indexer:k3d \
  rm-explorer-api:k3d \
  rm-dapp:k3d \
  rm-gateway-deployer:k3d \
  --cluster "$CLUSTER_NAME"

# ---------------------------------------------------------------------------
# 3. Apply manifests + override fork-rpc secret with real values.
# ---------------------------------------------------------------------------
echo "[k3d-up] applying manifests"
kubectl apply -k deploy/k3d/

# Override the fork-rpc Secret with the real archive RPC. Using
# `kubectl create --dry-run=client -o yaml | apply -f -` keeps this
# idempotent without leaking the URL into the kustomize tree.
kubectl create secret generic fork-rpc \
  --namespace robotmoney \
  --from-literal="RMPC_FORK_RPC_URL=$RMPC_FORK_RPC_URL" \
  --from-literal="RMPC_FORK_BLOCK=$RMPC_FORK_BLOCK" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic postgres-credentials \
  --namespace robotmoney \
  --from-literal="POSTGRES_PASSWORD=$POSTGRES_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart anvil-fork pod to pick up the real fork-rpc secret values.
kubectl -n robotmoney rollout restart deployment/anvil-fork
kubectl -n robotmoney rollout status deployment/anvil-fork --timeout=180s

# ---------------------------------------------------------------------------
# 4. Wait for gateway-deployer Job + extract deployment artifact.
# ---------------------------------------------------------------------------
echo "[k3d-up] waiting for gateway-deployer Job"
# Re-trigger the Job in case anvil restarted; delete + reapply just the Job.
kubectl -n robotmoney delete job gateway-deployer --ignore-not-found
kubectl apply -k deploy/k3d/

# Wait for the Job to complete (10 min cap).
if ! kubectl -n robotmoney wait --for=condition=complete --timeout=600s job/gateway-deployer; then
  echo "[k3d-up] gateway-deployer Job did not complete; logs follow:" >&2
  kubectl -n robotmoney logs job/gateway-deployer || true
  exit 1
fi

# Extract the deployment artifact from the Job's Pod (container is still
# alive due to the trailing `sleep 5`). Retry briefly to race the sleep.
DEPLOY_POD=$(kubectl -n robotmoney get pods -l app=gateway-deployer -o jsonpath='{.items[0].metadata.name}')
echo "[k3d-up] copying deployment artifact from $DEPLOY_POD"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
for i in $(seq 1 10); do
  if kubectl -n robotmoney cp "$DEPLOY_POD:/shared/full-stack.json" "$TMP/full-stack.json" 2>/dev/null; then
    break
  fi
  sleep 2
done
if [ ! -s "$TMP/full-stack.json" ]; then
  echo "[k3d-up] failed to copy deployment artifact" >&2
  exit 1
fi

# Apply as a ConfigMap so the indexer Deployment can mount it.
kubectl create configmap deployment-artifact \
  --namespace robotmoney \
  --from-file="full-stack.json=$TMP/full-stack.json" \
  --dry-run=client -o yaml | kubectl apply -f -

# Persist a copy on the host so the runbook commands work outside the cluster.
mkdir -p deployments
cp "$TMP/full-stack.json" deployments/full-stack.json

# ---------------------------------------------------------------------------
# 5. Roll out indexer + api + dapp.
# ---------------------------------------------------------------------------
echo "[k3d-up] rolling out indexer/api/dapp"
kubectl -n robotmoney rollout restart deployment/explorer-indexer
kubectl -n robotmoney rollout status  deployment/explorer-indexer --timeout=180s
kubectl -n robotmoney rollout status  deployment/explorer-api     --timeout=180s
kubectl -n robotmoney rollout status  deployment/dapp             --timeout=180s

# ---------------------------------------------------------------------------
# 6. Poll explorer-api /health from the host.
# ---------------------------------------------------------------------------
echo "[k3d-up] polling http://127.0.0.1:8080/health"
for i in $(seq 1 60); do
  if curl -fsS http://127.0.0.1:8080/health >/dev/null; then
    echo "[k3d-up] explorer-api healthy after ${i}s"
    echo "[k3d-up] devnet ready"
    echo "  anvil-fork    http://127.0.0.1:8545"
    echo "  postgres      127.0.0.1:5432"
    echo "  explorer-api  http://127.0.0.1:8080"
    echo "  dapp          http://127.0.0.1:5173"
    exit 0
  fi
  sleep 2
done

echo "[k3d-up] explorer-api did not become healthy within 120s" >&2
kubectl -n robotmoney get pods
exit 1
