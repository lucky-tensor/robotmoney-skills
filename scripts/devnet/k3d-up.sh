#!/usr/bin/env bash
# Single-command bring-up for the full-stack k3d devnet.
#
# Canonical: docs/technical/full-stack-devnet.md §"k3d single-command bring-up"
# Issue:     #146.
#
# Steps:
#   1. Create (or reuse) a k3d cluster with the same host port surface as
#      docker-compose.full-stack.yaml (8545/5432/8080/5173).
#   2. Build the three custom images (explorer-indexer, explorer-api,
#      dapp) and `k3d image import` them. (No gateway-deployer image —
#      the fork-state fixture already contains the deployed contracts.)
#   3. Apply the kustomize tree at deploy/k3d/.
#   4. Override the `fork-state` ConfigMap with the real contents of
#      `testing/fixtures/fork-state/CURRENT.anvil-state` and the
#      `deployment-artifact` ConfigMap with `deployments/full-stack.json`,
#      then restart anvil-fork so it loads the real state.
#   5. Roll out indexer + api + dapp.
#   6. Poll `explorer-api /health` from the host until 200.
#
# This script never contacts an upstream RPC. The fork-state fixture is
# refreshed offline by `scripts/devnet/snapshot-fork.sh`.
#
# Optional env (with defaults):
#   K3D_CLUSTER_NAME     cluster name (default rm-devnet)
#   POSTGRES_PASSWORD    devnet password (default rmoney_dev)
#
# Idempotent: re-running reuses an existing cluster, re-imports images,
# and re-applies manifests.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

CLUSTER_NAME="${K3D_CLUSTER_NAME:-rm-devnet}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-rmoney_dev}"

FIXTURE_STATE="testing/fixtures/fork-state/CURRENT.anvil-state"
FIXTURE_MANIFEST="testing/fixtures/fork-state/CURRENT.json"
DEPLOY_ARTIFACT="deployments/full-stack.json"

if [ ! -s "$FIXTURE_STATE" ] || [ ! -s "$FIXTURE_MANIFEST" ]; then
  echo "ERROR: fork-state fixture missing at $FIXTURE_STATE" >&2
  echo "       run: bash scripts/devnet/snapshot-fork.sh" >&2
  exit 1
fi
if [ ! -s "$DEPLOY_ARTIFACT" ]; then
  echo "ERROR: deployment artifact missing at $DEPLOY_ARTIFACT" >&2
  echo "       run: bash scripts/devnet/snapshot-fork.sh" >&2
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

echo "[k3d-up] importing images into k3d"
k3d image import \
  rm-explorer-indexer:k3d \
  rm-explorer-api:k3d \
  rm-dapp:k3d \
  --cluster "$CLUSTER_NAME"

# ---------------------------------------------------------------------------
# 3. Apply manifests.
# ---------------------------------------------------------------------------
echo "[k3d-up] applying manifests"
kubectl apply -k deploy/k3d/

# ---------------------------------------------------------------------------
# 4. Override the fork-state + deployment-artifact ConfigMaps with real
#    contents, then restart anvil-fork to load the real state.
# ---------------------------------------------------------------------------
echo "[k3d-up] uploading fork-state fixture as ConfigMap (size=$(wc -c < "$FIXTURE_STATE") bytes)"
kubectl create configmap fork-state \
  --namespace robotmoney \
  --from-file="CURRENT.anvil-state=$FIXTURE_STATE" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "[k3d-up] uploading deployment artifact as ConfigMap"
kubectl create configmap deployment-artifact \
  --namespace robotmoney \
  --from-file="full-stack.json=$DEPLOY_ARTIFACT" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic postgres-credentials \
  --namespace robotmoney \
  --from-literal="POSTGRES_PASSWORD=$POSTGRES_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart anvil-fork pod so it re-mounts the ConfigMap with the real
# state and reloads it via --load-state.
echo "[k3d-up] restarting anvil-fork to consume real fork-state"
kubectl -n robotmoney rollout restart deployment/anvil-fork
kubectl -n robotmoney rollout status deployment/anvil-fork --timeout=180s

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
