#!/usr/bin/env bash
# Generate a fresh Anvil fork-state fixture for the full-stack devnet.
#
# Canonical: docs/technical/full-stack-devnet.md §"Fork-state fixture"
# Issue:     #146.
#
# What this script does (developer-run; NOT executed in CI per run):
#
#   1. Reads RMPC_FORK_RPC_URL from env (default: https://base-rpc.publicnode.com).
#   2. Queries the upstream for the current Base block number.
#   3. Boots a local Anvil forking that block and chain-id 8453.
#   4. Runs contracts/script/Deploy.s.sol so the gateway/vault/USDC
#      deployment becomes part of the cached state.
#   5. Calls anvil_dumpState via JSON-RPC and writes the resulting hex
#      blob, plus metadata, to:
#          testing/fixtures/fork-state/base-<BLOCK>.json
#   6. Updates testing/fixtures/fork-state/CURRENT.json to point at the
#      new fixture and records the deployment artifact addresses.
#   7. Tears down Anvil cleanly.
#
# The generated fixture file is checked into the repository (size: a few
# MB). CI loads it via `anvil --load-state` so no upstream RPC is needed
# at runtime.
#
# Re-running this script just creates a new dated fixture and updates
# CURRENT.json — it never deletes old fixtures.
#
# Required tools on PATH: anvil, cast, forge, jq, curl.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

RMPC_FORK_RPC_URL="${RMPC_FORK_RPC_URL:-https://base-rpc.publicnode.com}"
FORK_CHAIN_ID="${FORK_CHAIN_ID:-8453}"
ANVIL_PORT="${ANVIL_PORT:-18545}"
ANVIL_HOST="127.0.0.1"
ANVIL_RPC="http://${ANVIL_HOST}:${ANVIL_PORT}"

FIXTURE_DIR="testing/fixtures/fork-state"
mkdir -p "$FIXTURE_DIR"

for tool in anvil cast forge jq curl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: required tool '$tool' not on PATH" >&2
    exit 1
  fi
done

# 1. Look up the current upstream block number.
echo "[snapshot] querying upstream block number from $RMPC_FORK_RPC_URL"
UPSTREAM_BLOCK_HEX=$(curl -sS -X POST -H 'content-type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' \
  "$RMPC_FORK_RPC_URL" | jq -r '.result')

if [ -z "$UPSTREAM_BLOCK_HEX" ] || [ "$UPSTREAM_BLOCK_HEX" = "null" ]; then
  echo "ERROR: failed to read eth_blockNumber from upstream" >&2
  exit 1
fi
# Pin 100 blocks behind tip to stay clear of reorg risk
# (matches docs/technical/fork-e2e-decisions.md §3.2 cadence note).
TIP=$((UPSTREAM_BLOCK_HEX))
PIN_BLOCK=$((TIP - 100))
echo "[snapshot] upstream tip=$TIP pinning at block=$PIN_BLOCK"

# 2. Boot Anvil with --dump-state so the structured JSON snapshot is
#    written on shutdown. (`anvil_dumpState` JSON-RPC returns a
#    gzipped-hex blob that `--load-state` does NOT accept; only the
#    `--dump-state` file format round-trips into `--load-state`.)
ANVIL_LOG=$(mktemp)
ANVIL_STATE_FILE_TMP=$(mktemp -t anvil-state.XXXXXX.json)
rm -f "$ANVIL_STATE_FILE_TMP"  # anvil writes it; must not exist
echo "[snapshot] starting anvil --fork-url <upstream> --fork-block-number $PIN_BLOCK"
anvil \
  --fork-url "$RMPC_FORK_RPC_URL" \
  --fork-block-number "$PIN_BLOCK" \
  --chain-id "$FORK_CHAIN_ID" \
  --host "$ANVIL_HOST" \
  --port "$ANVIL_PORT" \
  --mnemonic "test test test test test test test test test test test junk" \
  --accounts 10 \
  --balance 10000 \
  --dump-state "$ANVIL_STATE_FILE_TMP" \
  --silent \
  >"$ANVIL_LOG" 2>&1 &
ANVIL_PID=$!

cleanup() {
  if kill -0 "$ANVIL_PID" 2>/dev/null; then
    echo "[snapshot] tearing down anvil (pid=$ANVIL_PID)"
    # SIGINT (not SIGTERM) so anvil flushes --dump-state on exit.
    kill -INT "$ANVIL_PID" 2>/dev/null || true
    for _ in $(seq 1 30); do
      kill -0 "$ANVIL_PID" 2>/dev/null || break
      sleep 1
    done
    kill -KILL "$ANVIL_PID" 2>/dev/null || true
    wait "$ANVIL_PID" 2>/dev/null || true
  fi
  rm -f "$ANVIL_LOG"
}
trap cleanup EXIT

# Wait for Anvil to accept JSON-RPC.
for i in $(seq 1 60); do
  if cast chain-id --rpc-url "$ANVIL_RPC" >/dev/null 2>&1; then
    echo "[snapshot] anvil ready after ${i}s"
    break
  fi
  if ! kill -0 "$ANVIL_PID" 2>/dev/null; then
    echo "ERROR: anvil exited prematurely; log follows:" >&2
    cat "$ANVIL_LOG" >&2
    exit 1
  fi
  sleep 1
done

if ! cast chain-id --rpc-url "$ANVIL_RPC" >/dev/null 2>&1; then
  echo "ERROR: anvil did not become ready within 60s" >&2
  cat "$ANVIL_LOG" >&2
  exit 1
fi

# 3. Run the deploy script so its addresses are cached in Anvil state.
echo "[snapshot] running forge script Deploy"
export ADMIN_ADDRESS="${ADMIN_ADDRESS:-0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266}"
export PAUSER_ADDRESS="${PAUSER_ADDRESS:-0x70997970C51812dc3A010C7d01b50e0d17dc79C8}"
export AGENT_ADDRESS="${AGENT_ADDRESS:-0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC}"
export SHARE_RECEIVER_ADDRESS="${SHARE_RECEIVER_ADDRESS:-0x90F79bf6EB2c4f870365E785982E1f101E93b906}"
DEPLOYMENT_OUT_TMP=$(mktemp -t deploy.full-stack.XXXXXX.json)
export DEPLOYMENT_OUT="$DEPLOYMENT_OUT_TMP"

# Foundry test mnemonic index 0 (matches devnet ADMIN_ADDRESS).
DEPLOYER_PK="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

forge script contracts/script/Deploy.s.sol:Deploy \
  --rpc-url "$ANVIL_RPC" \
  --private-key "$DEPLOYER_PK" \
  --broadcast --slow

if [ ! -s "$DEPLOYMENT_OUT_TMP" ]; then
  echo "ERROR: forge script did not write deployment artifact" >&2
  exit 1
fi

# 3b. Warm well-known upstream addresses so their code+storage are
#     cached in Anvil's state dump and `--load-state` consumers can
#     read them WITHOUT contacting the upstream RPC.
#
#     Listed addresses are referenced by:
#       - testing/opencode-walkthrough/fixtures/rmpc-fork.toml.template
#       - rmpc / walkthrough tests that hit Base mainnet USDC and vault
#     Add new addresses here when a downstream test grows a hard-coded
#     mainnet contract reference.
WARM_ADDRESSES=(
  # Base mainnet USDC (Circle).
  "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
  # Walkthrough fixture vault (placeholder; cast read returns empty bytecode if absent).
  "0xCd9BB6428180c89cC0E5b9F1Bf6Bb98155Cf9CFf"
)
echo "[snapshot] warming well-known addresses (caching code in fork state)"
for addr in "${WARM_ADDRESSES[@]}"; do
  # Anvil's --dump-state only serializes accounts that have been
  # *modified*. Lazy-fetched fork accounts are read-through cached but
  # NOT included in the dump. Re-set their code via anvil_setCode to
  # mark them dirty so the dump captures their bytecode.
  CODE=$(cast code "$addr" --rpc-url "$ANVIL_RPC")
  if [ -z "$CODE" ] || [ "$CODE" = "0x" ]; then
    echo "[snapshot]   $addr: no code on upstream; skipping"
    continue
  fi
  curl -sS -X POST -H 'content-type: application/json' \
    --data "$(jq -n --arg a "$addr" --arg c "$CODE" \
      '{jsonrpc:"2.0",id:1,method:"anvil_setCode",params:[$a,$c]}')" \
    "$ANVIL_RPC" >/dev/null
  echo "[snapshot]   $addr: cached $(printf '%s' "$CODE" | wc -c) hex chars of bytecode"
done

# 4. Trigger Anvil's on-shutdown --dump-state by sending SIGINT, then
#    waiting for the file to appear.
echo "[snapshot] flushing --dump-state via SIGINT"
kill -INT "$ANVIL_PID"
for i in $(seq 1 60); do
  if [ -s "$ANVIL_STATE_FILE_TMP" ] && ! kill -0 "$ANVIL_PID" 2>/dev/null; then
    break
  fi
  sleep 1
done
wait "$ANVIL_PID" 2>/dev/null || true
if [ ! -s "$ANVIL_STATE_FILE_TMP" ]; then
  echo "ERROR: anvil --dump-state did not produce a state file" >&2
  cat "$ANVIL_LOG" >&2
  exit 1
fi
# Sanity: the file is JSON.
if ! jq -e . "$ANVIL_STATE_FILE_TMP" >/dev/null 2>&1; then
  echo "ERROR: --dump-state output is not valid JSON" >&2
  exit 1
fi

# 5. Write fixture + manifest. The --dump-state JSON IS the load-state
#    file; we copy it under the canonical name and wrap a tiny metadata
#    envelope alongside it.
CAPTURED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
FIXTURE_FILE="$FIXTURE_DIR/base-${PIN_BLOCK}.json"
ANVIL_STATE_FILE="$FIXTURE_DIR/base-${PIN_BLOCK}.anvil-state"
echo "[snapshot] writing fixture $FIXTURE_FILE"
cp "$ANVIL_STATE_FILE_TMP" "$ANVIL_STATE_FILE"
rm -f "$ANVIL_STATE_FILE_TMP"

DEPLOYMENT_JSON=$(cat "$DEPLOYMENT_OUT_TMP")
rm -f "$DEPLOYMENT_OUT_TMP"

jq -n \
  --arg chain_id "$FORK_CHAIN_ID" \
  --arg fork_block "$PIN_BLOCK" \
  --arg captured_at "$CAPTURED_AT" \
  --arg upstream_rpc "$RMPC_FORK_RPC_URL" \
  --arg state_file "base-${PIN_BLOCK}.anvil-state" \
  --argjson deployment "$DEPLOYMENT_JSON" \
  '{
    chain_id: ($chain_id | tonumber),
    fork_block: ($fork_block | tonumber),
    captured_at: $captured_at,
    upstream_rpc: $upstream_rpc,
    state_file: $state_file,
    deployment: $deployment
  }' > "$FIXTURE_FILE"

# 6. Update the stable pointers. Consumers (compose, k3d, CI) read
#    CURRENT.anvil-state directly via `anvil --load-state`. CURRENT.json
#    carries the metadata for humans + CI guards.
CURRENT_FILE="$FIXTURE_DIR/CURRENT.json"
CURRENT_STATE_FILE="$FIXTURE_DIR/CURRENT.anvil-state"
cp "$ANVIL_STATE_FILE" "$CURRENT_STATE_FILE"

jq -n \
  --arg fixture "base-${PIN_BLOCK}.json" \
  --arg state_file "base-${PIN_BLOCK}.anvil-state" \
  --arg fork_block "$PIN_BLOCK" \
  --arg chain_id "$FORK_CHAIN_ID" \
  --arg captured_at "$CAPTURED_AT" \
  '{
    fixture: $fixture,
    state_file: $state_file,
    fork_block: ($fork_block | tonumber),
    chain_id: ($chain_id | tonumber),
    captured_at: $captured_at
  }' > "$CURRENT_FILE"

# 7. Persist a copy of the deployment artifact at the canonical path so
#    the indexer (and CI smoke jobs) can read it without re-running the
#    deployer.
mkdir -p deployments
printf '%s' "$DEPLOYMENT_JSON" > deployments/full-stack.json

echo "[snapshot] done."
echo "  fixture     : $FIXTURE_FILE"
echo "  state_file  : $ANVIL_STATE_FILE"
echo "  current     : $CURRENT_FILE"
echo "  deployments : deployments/full-stack.json"
