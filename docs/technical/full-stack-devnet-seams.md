# Full-Stack Hosted Devnet — Seam Map

> **Canonical:** `docs/implementation-plan.md` §11–12 (Phase 5 Explorer,
> Phase 6 Human Dapp).
> **Scout issue:** #148.  **Implementation issue:** #146.
>
> This document captures service boundaries, port assignments, dependency
> order, health checks, shared configuration, and compose-vs-k3d
> recommendations discovered during the Phase 4.5 scout pass. It is the
> primary input to implementing `docker-compose.full-stack.yaml` and the
> `deploy/k3d/` manifests in issue #146.

---

## 1. Service inventory

| # | Service | Image / build path | Host port | Internal port | Dependency |
|---|---|---|---|---|---|
| 1 | `anvil-fork` | `ghcr.io/foundry-rs/foundry:latest` or local binary | 8545 | 8545 | — |
| 2 | `gateway-deployer` | same Foundry image (one-shot Job) | — | — | anvil-fork healthy |
| 3 | `postgres` | `postgres:16-alpine` | 5432 | 5432 | — |
| 4 | `explorer-indexer` | `services/explorer-indexer/Dockerfile` (Rust, to be created) | — | — | postgres ready + gateway-deployer succeeded |
| 5 | `explorer-api` | `clients/explorer-api/Dockerfile` (Rust, to be created) | 8080 | 8080 | postgres ready + explorer-indexer started |
| 6 | `dapp` | `clients/dapp/Dockerfile` (Vite/React, to be created) | 5173 | 5173 | — (can start independently; reaches API at build time via env) |

**rmpc binary** is not a long-running service. It runs as an operator CLI
from outside the compose network against the mapped port 8545. No container
needed.

---

## 2. Startup order and dependency graph

```
[postgres]          ──┐
                       ├──► [explorer-indexer]──► [explorer-api]
[anvil-fork]        ──┤
       │               │
       └──► [gateway-deployer (Job)] ──► (writes deployments/full-stack.json)
                                           consumed by explorer-indexer env

[dapp]  (independent; config is baked in at build time via VITE_* env)
```

Critical sequencing:

1. `anvil-fork` must pass its health check before `gateway-deployer` starts.
2. `gateway-deployer` must exit 0 (contract addresses written to
   `deployments/full-stack.json`) before `explorer-indexer` starts.
3. `postgres` migrations must apply before indexer writes any rows.
4. `explorer-api` can start as soon as `postgres` is reachable (it exposes
   `/health` immediately; it returns no data until the indexer has indexed).

---

## 3. Health checks

| Service | Proposed health check | Interval / retries |
|---|---|---|
| `anvil-fork` | `cast block-number --rpc-url http://localhost:8545` exits 0 | 5 s / 20 |
| `postgres` | `pg_isready -U $POSTGRES_USER` | 3 s / 10 |
| `explorer-api` | `curl -sf http://localhost:8080/health` | 5 s / 12 |
| `gateway-deployer` | n/a — compose `condition: service_completed_successfully` | — |
| `explorer-indexer` | liveness only: process alive | — |
| `dapp` | `curl -sf http://localhost:5173/` | 10 s / 6 |

---

## 4. Shared configuration seams

### 4.1 Files that will be created or modified

| File | Owner | Variables |
|---|---|---|
| `.env.example` | repo root | All vars listed below |
| `deployments/full-stack.json` | written by `gateway-deployer` at runtime | `gateway`, `usdc`, `vault`, `gateway_runtime_hash` |
| `clients/dapp/Dockerfile` | to be created | `VITE_FORK_RPC_URL`, `VITE_EXPLORER_API_URL`, `VITE_DAPP_BROWSER_KEYGEN_ENABLED` |
| `services/explorer-indexer/Dockerfile` | to be created | `DATABASE_URL`, `INDEXER_RPC_URL`, `INDEXER_GATEWAY`, `INDEXER_VAULT`, `INDEXER_FROM_BLOCK` |
| `clients/explorer-api/Dockerfile` | to be created | `DATABASE_URL`, `EXPLORER_API_PORT` |

### 4.2 Required environment variables

```
# Anvil fork
RMPC_FORK_RPC_URL          # upstream archive RPC (secret in CI)
RMPC_FORK_BLOCK            # pinned block number (e.g. 29800000)
FORK_CHAIN_ID=8453
ANVIL_MNEMONIC             # mnemonic for pre-funded accounts

# Postgres
POSTGRES_USER
POSTGRES_PASSWORD
POSTGRES_DB

# Explorer indexer
INDEXER_RPC_URL=http://anvil-fork:8545
INDEXER_GATEWAY            # read from deployments/full-stack.json
INDEXER_VAULT              # read from deployments/full-stack.json
INDEXER_FROM_BLOCK=0

# Explorer API
EXPLORER_API_PORT=8080
DATABASE_URL               # postgres connection string

# Dapp (build args — baked into browser bundle at docker build time)
VITE_FORK_RPC_URL=http://localhost:8545
VITE_EXPLORER_API_URL=http://localhost:8080
VITE_DAPP_BROWSER_KEYGEN_ENABLED=false
```

### 4.3 Deployment artifact handoff

`gateway-deployer` writes `deployments/full-stack.json` to the bind-mounted
repo root (pattern already established in
`testing/ethereum-testnet/config/docker-compose.deployer.yaml`). The indexer
reads `INDEXER_GATEWAY` / `INDEXER_VAULT` from this file via an entrypoint
script, or these values are injected by a compose `entrypoint` override that
does `jq` extraction and `exec`.

---

## 5. Reusable commands and gaps identified

### Reusable from existing compose/CI

| Source | What is reusable |
|---|---|
| `testing/ethereum-testnet/config/docker-compose.yaml` | Anvil / Geth pattern; health check convention; genesis volume setup |
| `testing/ethereum-testnet/config/docker-compose.deployer.yaml` | `gateway-deployer` Job pattern (bind-mount repo root, forge script, JSON output, smoke cast call) — copy-adapt for Anvil fork instead of Geth |
| `.github/workflows/fork-e2e.yml` | `RMPC_FORK_RPC_URL` skip-when-missing pattern for CI |
| `.github/workflows/demo-e2e.yml` | Anvil fork boot + deploy script steps |

### Gaps (no existing artifact)

| Gap | What must be created in #146 |
|---|---|
| `services/explorer-indexer/` | Rust crate + Dockerfile for Postgres indexer |
| `clients/explorer-api/` | Rust crate + Dockerfile for HTTP API |
| `clients/dapp/Dockerfile` | Vite build container; no Dockerfile exists today |
| `docker-compose.full-stack.yaml` | Six-service compose in repo root |
| `deploy/k3d/` | Kubernetes manifests |
| `scripts/devnet/k3d-up.sh` / `k3d-down.sh` | Cluster lifecycle scripts |
| `.github/workflows/_devnet-k3d.yml` | Reusable CI workflow |
| `docs/technical/full-stack-devnet.md` | Runbook (this document is the seam map; the runbook is a separate deliverable of #146) |
| `.env.example` | Variable reference (none exists today) |

---

## 6. Compose-only vs. k3d recommendation

**Compose-only is sufficient for local development** but is NOT sufficient
for hosted CI / demo runs at scale. The rationale:

| Criterion | Compose | k3d |
|---|---|---|
| Local one-command bring-up | Yes | Yes (with k3d install) |
| GitHub-hosted runner support | Yes (no extra tooling) | Yes (k3d installs in ~20 s on ubuntu-latest) |
| Port isolation between concurrent jobs | No — host ports collide | Yes — each cluster gets a namespace |
| Image build caching in CI | Straightforward | Requires `k3d image import`; cache layers portable |
| Multi-replica / rolling-deploy testing | Not practical | Native |
| Production-parity for hosted demo | Low (compose is dev-only tooling) | High (Kubernetes resource model) |

**Recommendation:** implement the compose milestone first (simpler, unblocks
local dev and basic CI) and the k3d milestone second. The two milestones are
already split in issue #146. The compose file and the k3d manifests share the
same six-service graph and the same env-var contract, so the compose file
serves as the authoritative topology reference that the k3d manifests mirror.

**k3d must be first-class** for any workflow that claims "hosted devnet"
semantics (persistent URL, CI-reusable, zero port conflicts). Compose alone
is not sufficient there.

---

## 7. Integration risks

| Risk | Severity | Mitigation |
|---|---|---|
| `gateway-deployer` writes `deployments/full-stack.json` at runtime; indexer start depends on it | High | Entrypoint script reads file and loops/fails fast; compose `depends_on: condition: service_completed_successfully` enforces ordering |
| Dapp build args are baked at `docker build` time, not runtime | Medium | Pass `VITE_*` as `--build-arg` in compose `build:` section; document in `.env.example` |
| explorer-indexer and explorer-api crates do not exist yet | High | Issue #146 must create both; scout identifies no existing Rust source to adapt |
| Postgres migration state vs. first-run idempotency | Medium | Use `sqlx migrate run` in indexer entrypoint; add `IF NOT EXISTS` guards |
| k3d `image import` adds ~30–60 s to CI bring-up | Low | Accept; document in runbook; gate `k3d-smoke` job on a separate CI path |
| CORS: explorer-api returns data to dapp running on different port | Medium | Issue #166 already tracks adding CORS configuration to explorer-api |
| Port conflicts in matrix CI (8545 shared by fork-e2e and full-stack jobs) | Medium | k3d namespacing resolves this; compose jobs need `concurrency:` group in CI |

---

## 8. Per-service startup command summary

| Service | Local startup command (outside compose) |
|---|---|
| `anvil-fork` | `anvil --fork-url $RMPC_FORK_RPC_URL --fork-block-number $RMPC_FORK_BLOCK --chain-id 8453 --port 8545` |
| `gateway-deployer` | `forge script contracts/script/Deploy.s.sol:Deploy --rpc-url http://127.0.0.1:8545 --broadcast ...` |
| `postgres` | `docker run -e POSTGRES_USER=... -e POSTGRES_PASSWORD=... -e POSTGRES_DB=... -p 5432:5432 postgres:16-alpine` |
| `explorer-indexer` | `cargo run --bin explorer-indexer` (crate TBD, `services/explorer-indexer/`) |
| `explorer-api` | `cargo run --bin explorer-api` (crate TBD, `clients/explorer-api/`) |
| `dapp` | `cd clients/dapp && npm run dev` (Vite dev server on port 5173) |
| `rmpc` (operator CLI) | `rmpc self-check --config /path/to/config.toml` |

---

## 9. Scout findings summary (for issue #146)

1. Six services required; only `anvil-fork` and `gateway-deployer` have
   existing Docker / compose definitions. Four services need new Dockerfiles.
2. Deployment artifact handoff (`deployments/full-stack.json`) is the key
   runtime dependency seam — all downstream services depend on it.
3. Compose-only is sufficient for the compose milestone; k3d is required for
   the hosted/CI milestone. Both milestones are already scoped in #146.
4. Issue #166 (CORS) must be resolved or the dapp milestone will be broken.
5. `.env.example` must be created from scratch — no existing template.
6. The `deploy/k3d/` manifests are a straightforward 1:1 lift of the compose
   graph with added Deployments, Services, a Job, and ConfigMaps.
