# Full-stack containerized devnet runbook

> **Canonical:** `docs/implementation-plan.md` §2 (Phase 1 gateway + vault),
> §11 (Phase 5 explorer), §12 (Phase 6 dapp).
> **Issue:** #146.
>
> One documented command spins up the entire Robot Money stack against a
> public-chain fork: Anvil fork node, gateway/vault deployment, Postgres,
> the explorer indexer + API placeholders, and the dapp placeholder.

## Status

| Service | State | Notes |
|---|---|---|
| `anvil-fork` | Functional | Foundry Anvil with `--fork-url` + pinned block. |
| `gateway-deployer` | Functional | Runs `forge script Deploy` against the fork; writes `deployments/full-stack.json`. |
| `postgres` | Functional | Postgres 16; schema applied by the indexer once it lands. |
| `explorer-indexer` | Placeholder | Phase 5 not yet implemented. Container documents the env-var seam (`DATABASE_URL`, `RMPC_FORK_RPC_URL`) and exits 0. |
| `explorer-api` | Placeholder | Phase 5 not yet implemented. Reserves port `:8080` and `DATABASE_URL`. |
| `dapp` | Placeholder | Phase 6 dapp source is library-style — no Vite entrypoint yet. Reserves port `:5173` and `VITE_*` env contract. |

The placeholder services are intentional: they fix the compose-graph wiring,
port assignments, and env-var contract so that the Phase 5 / Phase 6
implementations can drop in by swapping `image:` and `command:` without
rewriting the compose file.

## One-command bring-up

```bash
# 1. Configure environment.
cp .env.example .env
# Edit .env to set RMPC_FORK_RPC_URL to a real archive RPC.

# 2. Boot the stack.
docker compose -f docker-compose.full-stack.yaml up
```

Expected sequence:

1. `anvil-fork` becomes healthy (cast chain-id returns).
2. `gateway-deployer` runs `forge build` + `forge script Deploy` and writes
   `deployments/full-stack.json` to the host. Container exits 0.
3. `postgres` becomes healthy.
4. `explorer-indexer`, `explorer-api`, `dapp` print their placeholder
   messages and exit 0.
5. `anvil-fork` and `postgres` continue running.

To run only the functional core (skip the placeholders):

```bash
docker compose -f docker-compose.full-stack.yaml up anvil-fork gateway-deployer postgres
```

## Required environment variables

| Var | Purpose | Example |
|---|---|---|
| `RMPC_FORK_RPC_URL` | Archive RPC for `anvil --fork-url`. | `https://base-mainnet.g.alchemy.com/v2/...` |
| `RMPC_FORK_BLOCK` | Pin block (refresh per ADR §3.2). | `29800000` |
| `POSTGRES_PASSWORD` | Postgres password. | `rmoney_dev` |

Optional overrides are documented inline in `.env.example`.

## Verifying `rmpc self-check` from the host

The Anvil fork publishes JSON-RPC on `127.0.0.1:8545` (mapped from the
container's `:8545`). After `gateway-deployer` exits, the gateway address
is in `deployments/full-stack.json` on the host:

```bash
GATEWAY=$(jq -r .gateway deployments/full-stack.json)
RMPC_RPC_URL=http://127.0.0.1:8545 \
RMPC_GATEWAY_ADDRESS="$GATEWAY" \
  cargo run -p rmpc -- self-check
```

`self-check` issues read-only RPCs (chain id, gateway view functions) and
exits non-zero if the gateway is unreachable or misconfigured.

## Verifying explorer event coverage

Once `services/explorer-indexer` lands (Phase 5):

```bash
# AgentDeposit indexed within ~1 block of emission.
curl -sf http://127.0.0.1:8080/v1/agents/$AGENT/deposits | jq '.[0]'
```

Until then the indexer is a placeholder; this section serves as the
acceptance contract Phase 5 must satisfy.

## k3d / Helm variant (stretch)

Not yet implemented. The compose file is the source of truth for service
wiring; a future `deploy/k3d/` directory will translate the same graph to
a Kubernetes manifest set or Helm chart. The compose service names map
1:1 to intended Deployment names.

## Troubleshooting

- **Anvil fork crashes on boot.** Confirm `RMPC_FORK_RPC_URL` supports
  archive reads at `RMPC_FORK_BLOCK`. Public RPCs without archive will
  return errors during state preload.
- **`gateway-deployer` cannot reach `anvil-fork`.** The deployer waits
  for the `service_healthy` condition; if Anvil is unhealthy the deployer
  never starts. Inspect `docker logs rm-anvil-fork`.
- **Port 8545 / 5432 already in use.** Stop other devnets first
  (`testing/ethereum-testnet/config/docker-compose.yaml` also binds 8545).
- **Deployment artifact missing.** The container writes
  `deployments/full-stack.json` via the bind-mount at `.:/repo`. Check
  host filesystem permissions on `deployments/` and the working directory.
