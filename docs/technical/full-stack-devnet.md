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
`Cargo.toml` / `package.json` fails fast.

## k3d / Helm variant (stretch)

Not yet implemented in this issue. The compose service names map 1:1 to
intended Deployment names. A future `deploy/k3d/` directory will translate
the same graph to a Kubernetes manifest set or Helm chart.

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
