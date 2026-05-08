# Full-stack containerized devnet runbook

> **Canonical:** `docs/implementation-plan.md` §2 (Phase 1 gateway + vault),
> §11 (Phase 5 explorer), §12 (Phase 6 dapp).
> **Issue:** #146.
>
> One documented command spins up the entire Robot Money stack against a
> public-chain fork: Anvil fork node, gateway/vault deployment, Postgres,
> the explorer indexer + API, and the human dapp.

## Service map

| Service | Image / Build context | Port (host) | Purpose |
|---|---|---|---|
| `anvil-fork` | `ghcr.io/foundry-rs/foundry:latest` | `8545` | Anvil fork at `RMPC_FORK_BLOCK`. |
| `gateway-deployer` | `ghcr.io/foundry-rs/foundry:latest` | — | One-shot Forge deploy; writes `deployments/full-stack.json`. |
| `postgres` | `postgres:16-alpine` | `5432` | Indexer + API database. |
| `explorer-indexer` | build `services/explorer-indexer/Dockerfile` | — | §11 long-running poll loop. Reads gateway/vault from deployment artifact. |
| `explorer-api` | build `clients/explorer-api/Dockerfile` | `8080` | §11 GET-only HTTP API. |
| `dapp` | build `clients/dapp/Dockerfile` | `5173` | §12 Vite-built bundle, served via `vite preview`. |

## One-command bring-up

```bash
# 1. Configure environment.
cp .env.example .env
# Edit .env to set RMPC_FORK_RPC_URL to a real archive RPC.

# 2. Boot the stack (first run builds three Rust/JS images; ~3-5 min).
docker compose -f docker-compose.full-stack.yaml up --build
```

Expected sequence:

1. `anvil-fork` becomes healthy (`cast chain-id` returns).
2. `gateway-deployer` runs `forge build` + `forge script Deploy`, writes
   `deployments/full-stack.json`, exits 0.
3. `postgres` becomes healthy.
4. `explorer-indexer` reads gateway+vault from the deployment artifact,
   applies migrations, and starts ticking.
5. `explorer-api` serves `/health` on `:8080`.
6. `dapp` serves on `:5173` (configured via build-time `VITE_*` args to
   point the browser at `http://localhost:8545` and `http://localhost:8080`).

To run only the chain + deploy (skip explorer + dapp):

```bash
docker compose -f docker-compose.full-stack.yaml up anvil-fork gateway-deployer
```

## Required environment variables

| Var | Purpose | Example |
|---|---|---|
| `RMPC_FORK_RPC_URL` | Archive RPC for `anvil --fork-url`. | `https://base-mainnet.g.alchemy.com/v2/...` |
| `RMPC_FORK_BLOCK` | Pin block (refresh per ADR §3.2). | `29800000` |
| `POSTGRES_PASSWORD` | Postgres password. | `rmoney_dev` |

Optional overrides (chain id, indexer tick, dapp env class, wallet flags)
are documented inline in `.env.example`.

## Verifying `rmpc self-check` from outside the compose network

The Anvil fork publishes JSON-RPC on `127.0.0.1:8545` (mapped from the
container's `:8545`). After `gateway-deployer` exits, the gateway address
is in `deployments/full-stack.json` on the host:

```bash
GATEWAY=$(grep -o '"gateway":[[:space:]]*"0x[0-9a-fA-F]*"' \
            deployments/full-stack.json | grep -o '0x[0-9a-fA-F]*')

RMPC_RPC_URL=http://127.0.0.1:8545 \
RMPC_GATEWAY_ADDRESS="$GATEWAY" \
  cargo run -p rmpc -- self-check
```

`self-check` issues read-only RPCs (chain id, gateway view functions) and
exits non-zero if the gateway is unreachable or misconfigured.

## Verifying explorer event coverage

Once the stack is up, deposit events are indexed within one tick
(`INDEXER_TICK_SECONDS`, default 12s):

```bash
# Health check
curl -fsS http://127.0.0.1:8080/health

# Deposits for the seeded agent address
AGENT=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
curl -sf "http://127.0.0.1:8080/v1/agents/$AGENT/deposits" | jq '.'

# Latest vault snapshot
curl -sf http://127.0.0.1:8080/v1/vault/snapshot/latest | jq '.'
```

After issuing a deposit through `rmpc deposit-once`, the deposit row
appears in `/v1/agents/$AGENT/deposits` within one tick. The API never
signs or writes — see `docs/implementation-plan.md` §11 "Boundaries".

## Connecting the dapp

Browse to `http://localhost:5173`. The bundle was built with:

- `VITE_FORK_RPC_URL=http://localhost:8545`
- `VITE_EXPLORER_API_URL=http://localhost:8080`
- `VITE_USE_MOCK_WALLET=true` (the mock wallet bypasses the browser
  extension requirement for devnet use; production builds set this to
  `false`).

For hosted deployments, override the `VITE_*` build args via `.env` or
`docker compose build --build-arg` so the bundle points at the public
hostnames.

## CI smoke test

`.github/workflows/full-stack-devnet.yml` exercises the compose graph on
every PR that touches the file or the Phase 5/6 service Dockerfiles. The
job runs `docker compose config` to validate the file and then builds the
three custom images (without booting them) so dependency drift in
`Cargo.toml` / `package.json` fails fast. A `manifest-validate` job in
the same workflow renders `deploy/k3d/` with `kubectl kustomize` so
manifest-level breakage fails fast, and a nightly `k3d-smoke` job boots
the live cluster end-to-end (see below).

## k3d single-command bring-up

Same six services, same host port surface (8545/5432/8080/5173), running
inside a [k3d](https://k3d.io) Kubernetes cluster instead of Compose.
Manifests live under `deploy/k3d/` and are applied through a
kustomization so the bring-up is a single `kubectl apply -k`. The
script-level entry point handles cluster create, image build/import,
manifest apply, deploy-Job extraction, and the final
`explorer-api /health` poll.

### Prerequisites

- [`docker`](https://docs.docker.com/engine/install/) (image build +
  k3d node runtime).
- [`k3d`](https://k3d.io) v5.7+ (`brew install k3d` or `curl -fsSL
  https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | TAG=v5.7.4
  bash`).
- [`kubectl`](https://kubernetes.io/docs/tasks/tools/) (any 1.27+ release
  works against the k3d-shipped k3s server).

### Required environment variables

The same vars as the Compose flow:

| Var | Purpose | Example |
|---|---|---|
| `RMPC_FORK_RPC_URL` | Archive RPC for `anvil --fork-url`. | `https://base-mainnet.g.alchemy.com/v2/...` |
| `RMPC_FORK_BLOCK` | Pin block (default `29800000`). | `29800000` |
| `POSTGRES_PASSWORD` | Postgres password (default `rmoney_dev`). | `rmoney_dev` |
| `K3D_CLUSTER_NAME` | Override cluster name (default `rm-devnet`). | `rm-devnet` |

### Bring up

```bash
export RMPC_FORK_RPC_URL=https://base-mainnet.g.alchemy.com/v2/<key>
export RMPC_FORK_BLOCK=29800000
bash scripts/devnet/k3d-up.sh
```

Expected sequence:

1. `k3d cluster create` (or reuse) with host ports
   `8545/5432/8080/5173` published through `k3d`'s built-in load
   balancer (`klipper-lb`).
2. `docker build` then `k3d image import` for the four custom images
   (`rm-explorer-indexer`, `rm-explorer-api`, `rm-dapp`,
   `rm-gateway-deployer` — the deployer is a fourth image because k3d
   cannot bind-mount the host repo into a vanilla Foundry container).
3. `kubectl apply -k deploy/k3d/` applies all six services.
4. The script overrides the placeholder `fork-rpc` Secret with the real
   archive RPC then restarts `anvil-fork` to pick it up.
5. `gateway-deployer` Job runs `forge script Deploy.s.sol` and writes
   `/shared/full-stack.json`; the script `kubectl cp`s it out, applies
   it as the `deployment-artifact` ConfigMap (consumed by the indexer
   Deployment), and persists a copy at `deployments/full-stack.json` on
   the host.
6. `explorer-indexer` rolls out and starts ticking; `explorer-api`
   becomes healthy on `:8080`; `dapp` serves on `:5173`.
7. The script polls `http://127.0.0.1:8080/health` and exits 0 on the
   first 200.

### Tear down

```bash
bash scripts/devnet/k3d-down.sh
```

Idempotent: succeeds whether or not the cluster exists.

### CI integration

`.github/workflows/_devnet-k3d.yml` is a reusable workflow (`uses:`)
that any caller can consume to provision the same devnet inside a
GitHub Actions runner. It wraps the
`.github/actions/devnet-k3d/action.yml` composite action, which is the
right granularity for callers that need to run their assertions in the
same job as the cluster (reusable workflows run on their own runner and
can't share cluster state with the caller).

Workflows that consume the reusable workflow (issue #146 migration):

- `fork-e2e.yml`
- `demo.yml`
- `opencode-walkthrough.yml`
- `opencode-headless-deposit.yml`
- `opencode-headless-read.yml`
- `dapp.yml` (Playwright path)

The nightly `k3d-smoke` job in `full-stack-devnet.yml` boots the live
cluster, submits an `agentDeposit`, asserts the explorer indexes the
event, then runs `k3d-down.sh` and re-runs it to assert idempotent
tear-down.

## Troubleshooting

- **Anvil fork crashes on boot.** Confirm `RMPC_FORK_RPC_URL` supports
  archive reads at `RMPC_FORK_BLOCK`. Public RPCs without archive will
  return errors during state preload.
- **`gateway-deployer` cannot reach `anvil-fork`.** The deployer waits for
  the `service_healthy` condition; if Anvil is unhealthy the deployer
  never starts. Inspect `docker logs rm-anvil-fork`.
- **`explorer-indexer` exits with "deployment artifact missing".** The
  indexer reads `deployments/full-stack.json`. Ensure `gateway-deployer`
  ran to completion (exit 0). Re-run with `docker compose up gateway-deployer`.
- **Port 8545 / 5432 / 8080 / 5173 already in use.** Stop other devnets
  (`testing/ethereum-testnet/config/docker-compose.yaml` also binds 8545)
  or override `EXPLORER_API_PORT` in `.env`.
- **Dapp cannot reach RPC / API.** The dapp bundle hard-codes the
  `VITE_*` URLs at build time. Rebuild with `docker compose build dapp`
  after changing `.env`.
