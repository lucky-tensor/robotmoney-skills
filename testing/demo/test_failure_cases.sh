#!/usr/bin/env bash
# Canonical: docs/technical/demo-runbook.md §11
# Implements: implementation-plan §13 (Phase 7 failure-case toggles). Issue: #116.
#
# Fork-backed test for the five failure-case demonstrations.
# Requires RMPC_FORK_RPC_URL and anvil on PATH; skips loud-clean otherwise.
#
# The test:
#   1. Boots an Anvil fork.
#   2. Creates three ephemeral keypairs (admin, pauser, agent).
#   3. Deploys the gateway stack via forge script.
#   4. Approves USDC allowance.
#   5. Runs rmpc deposit against a happy-path config (exit 0 expected).
#   6. Tests each of the five failure-case toggles in order.
#
# Exit codes:
#   0  — all five failure cases refused correctly (or skip-clean if no RPC).
#   1  — a failure case did not produce the expected refusal.
#   11 — required tool missing (anvil / forge / cast / rmpc).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RMPC_BIN="${RMPC_BIN:-$REPO_ROOT/clients/rust-payment-client/target/debug/rmpc}"
FORK_BLOCK="${RMPC_FORK_BLOCK:-29800000}"
FORK_RPC="${RMPC_FORK_RPC_URL:-}"

# Skip-clean when no archive RPC configured.
if [[ -z "$FORK_RPC" ]]; then
  echo "[demo-failure-cases] skip-clean: RMPC_FORK_RPC_URL not set."
  echo "[demo-failure-cases] Set RMPC_FORK_RPC_URL to a Base archive endpoint to run this test."
  exit 0
fi

# Check required tools.
for tool in anvil forge cast jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "[demo-failure-cases] missing required tool: $tool" >&2
    exit 11
  fi
done

if [[ ! -x "$RMPC_BIN" ]]; then
  echo "[demo-failure-cases] rmpc binary not found or not executable: $RMPC_BIN" >&2
  echo "[demo-failure-cases] Build it: cargo build --manifest-path clients/rust-payment-client/Cargo.toml --bin rmpc" >&2
  exit 11
fi

FAIL=0
err() { echo "FAIL: $*" >&2; FAIL=1; }
ok()  { echo "ok:   $*"; }

# -----------------------------------------------------------------------
# Setup: boot fork, create keys, deploy, approve.
# -----------------------------------------------------------------------
TMPDIR_DEMO=$(mktemp -d)
trap 'kill "$ANVIL_PID" 2>/dev/null || true; rm -rf "$TMPDIR_DEMO"' EXIT

# Pick a free port.
ANVIL_PORT=$(python3 -c "import socket; s=socket.socket(); s.bind(('',0)); print(s.getsockname()[1]); s.close()" 2>/dev/null || echo 18545)
FORK_RPC_LOCAL="http://127.0.0.1:$ANVIL_PORT"

echo "[demo-failure-cases] starting Anvil fork (block=$FORK_BLOCK, port=$ANVIL_PORT)..."
anvil \
  --fork-url  "$FORK_RPC" \
  --fork-block-number "$FORK_BLOCK" \
  --chain-id 8453 \
  --port "$ANVIL_PORT" \
  --silent \
  &
ANVIL_PID=$!

# Wait for RPC up.
for i in $(seq 1 40); do
  if cast chain-id --rpc-url "$FORK_RPC_LOCAL" >/dev/null 2>&1; then break; fi
  sleep 0.5
done
cast chain-id --rpc-url "$FORK_RPC_LOCAL" | grep -q 8453 || { echo "Anvil did not come up on chain 8453" >&2; exit 1; }
echo "[demo-failure-cases] fork up: chain_id=8453 block=$FORK_BLOCK"

# Create three throwaway keypairs.
ADMIN_JSON=$(cast wallet new --json 2>/dev/null)
PAUSER_JSON=$(cast wallet new --json 2>/dev/null)
AGENT_JSON=$(cast wallet new --json 2>/dev/null)

ADMIN_ADDRESS=$(echo "$ADMIN_JSON"  | jq -r .address)
ADMIN_PRIVKEY=$(echo "$ADMIN_JSON"  | jq -r .private_key)
PAUSER_ADDRESS=$(echo "$PAUSER_JSON" | jq -r .address)
PAUSER_PRIVKEY=$(echo "$PAUSER_JSON" | jq -r .private_key)
AGENT_ADDRESS=$(echo "$AGENT_JSON"  | jq -r .address)
AGENT_PRIVKEY=$(echo "$AGENT_JSON"  | jq -r .private_key)
SHARE_RECEIVER_ADDRESS="$ADMIN_ADDRESS"

# Fund all with ETH.
for addr in "$ADMIN_ADDRESS" "$PAUSER_ADDRESS" "$AGENT_ADDRESS"; do
  cast rpc anvil_setBalance "$addr" 0x56BC75E2D63100000 --rpc-url "$FORK_RPC_LOCAL" >/dev/null
done

# Deploy gateway stack.
DEPLOYMENT_OUT="$TMPDIR_DEMO/deployment.json"
echo "[demo-failure-cases] deploying gateway stack..."
export ADMIN_ADDRESS PAUSER_ADDRESS AGENT_ADDRESS SHARE_RECEIVER_ADDRESS DEPLOYMENT_OUT
forge script contracts/script/Deploy.s.sol:Deploy \
  --rpc-url "$FORK_RPC_LOCAL" \
  --private-key "$ADMIN_PRIVKEY" \
  --broadcast \
  --silent \
  2>/dev/null

GATEWAY_ADDRESS=$(jq -r .gateway "$DEPLOYMENT_OUT")
USDC_ADDRESS=$(jq -r .usdc "$DEPLOYMENT_OUT")
VAULT_ADDRESS=$(jq -r .vault "$DEPLOYMENT_OUT")
GATEWAY_RUNTIME_HASH=$(jq -r .gateway_runtime_hash "$DEPLOYMENT_OUT")
echo "[demo-failure-cases] gateway=$GATEWAY_ADDRESS usdc=$USDC_ADDRESS vault=$VAULT_ADDRESS"

# Create encrypted keystore.
KEYSTORE_PATH="$TMPDIR_DEMO/keystore.json"
RMPC_SIGNER_PASSPHRASE="demo-test-passphrase"
echo "$AGENT_PRIVKEY" | cast wallet import \
  --private-key-stdin \
  --password "$RMPC_SIGNER_PASSPHRASE" \
  "$KEYSTORE_PATH" >/dev/null 2>&1

# Approve 1000 USDC.
cast send "$USDC_ADDRESS" \
  "approve(address,uint256)(bool)" \
  "$GATEWAY_ADDRESS" 1000000000 \
  --rpc-url "$FORK_RPC_LOCAL" \
  --private-key "$AGENT_PRIVKEY" \
  --silent >/dev/null 2>&1

STATE_DIR="$TMPDIR_DEMO/rmpc-state"
mkdir -p "$STATE_DIR"

write_config() {
  local gw_hash="${1:-$GATEWAY_RUNTIME_HASH}"
  local fee_cap="${2:-100000000000}"
  cat > "$TMPDIR_DEMO/rmpc-config.toml" <<TOML
chain_id             = 8453
rpc_url              = "$FORK_RPC_LOCAL"
gateway_address      = "$GATEWAY_ADDRESS"
usdc_address         = "$USDC_ADDRESS"
vault_address        = "$VAULT_ADDRESS"
gateway_runtime_hash = "$gw_hash"
max_fee_per_gas_cap  = $fee_cap

[signer]
allow_software_fallback = true
keystore_path           = "$KEYSTORE_PATH"

state_dir = "$STATE_DIR"
TOML
}

export RMPC_SIGNER_PASSPHRASE

# -----------------------------------------------------------------------
# Happy path: expect exit 0.
# -----------------------------------------------------------------------
write_config
echo "[demo-failure-cases] happy path deposit..."
if "$RMPC_BIN" deposit \
    --config "$TMPDIR_DEMO/rmpc-config.toml" \
    --amount 100000000 \
    --order-id 0x1111111111111111111111111111111111111111111111111111111111111111 \
    >/dev/null 2>&1; then
  ok "happy path: deposit succeeded (exit 0)"
else
  err "happy path: deposit failed unexpectedly"
fi

# -----------------------------------------------------------------------
# Failure case 1: unauthorized agent (revoke AGENT_ROLE).
# -----------------------------------------------------------------------
echo "[demo-failure-cases] failure case 1: unauthorized agent..."

# Revoke agent authorization.
cast send "$GATEWAY_ADDRESS" \
  "revokeAgent(address)" \
  "$AGENT_ADDRESS" \
  --rpc-url "$FORK_RPC_LOCAL" \
  --private-key "$ADMIN_PRIVKEY" \
  --silent >/dev/null 2>&1

write_config
STDERR_OUT=$("$RMPC_BIN" deposit \
    --config "$TMPDIR_DEMO/rmpc-config.toml" \
    --amount 100000000 \
    --order-id 0x2222222222222222222222222222222222222222222222222222222222222222 \
    2>&1 >/dev/null || true)

if echo "$STDERR_OUT" | grep -qi "ErrAgentNotAuthorized\|not authorized\|unauthorized\|agent.*inactive\|preflight"; then
  ok "failure case 1: unauthorized agent refused (ErrAgentNotAuthorized / preflight)"
else
  err "failure case 1: expected ErrAgentNotAuthorized refusal, got: $STDERR_OUT"
fi

# Restore: re-authorize agent (requires ADMIN_ROLE; cast uses packed ABI).
# We use forge to re-run a partial deploy or cast with the gateway ABI.
# For simplicity, we re-impersonate admin to call authorizeAgent.
# The gateway's authorizeAgent(address,AgentPolicy) signature is complex;
# skip restore and use a fresh order-id for remaining cases.
# (Remaining cases use a config-level or USDC-level toggle that does not
# depend on agent being authorized — or we re-deploy for each case.)
# For the allowance case we need agent to be authorized again; re-deploy.
DEPLOYMENT_OUT2="$TMPDIR_DEMO/deployment2.json"
export DEPLOYMENT_OUT="$DEPLOYMENT_OUT2"
forge script contracts/script/Deploy.s.sol:Deploy \
  --rpc-url "$FORK_RPC_LOCAL" \
  --private-key "$ADMIN_PRIVKEY" \
  --broadcast \
  --silent \
  2>/dev/null

GATEWAY_ADDRESS=$(jq -r .gateway "$DEPLOYMENT_OUT2")
USDC_ADDRESS=$(jq -r .usdc "$DEPLOYMENT_OUT2")
VAULT_ADDRESS=$(jq -r .vault "$DEPLOYMENT_OUT2")
GATEWAY_RUNTIME_HASH=$(jq -r .gateway_runtime_hash "$DEPLOYMENT_OUT2")

# Approve 1000 USDC for the new gateway.
cast send "$USDC_ADDRESS" \
  "approve(address,uint256)(bool)" \
  "$GATEWAY_ADDRESS" 1000000000 \
  --rpc-url "$FORK_RPC_LOCAL" \
  --private-key "$AGENT_PRIVKEY" \
  --silent >/dev/null 2>&1

# -----------------------------------------------------------------------
# Failure case 2: insufficient allowance (zero USDC allowance).
# -----------------------------------------------------------------------
echo "[demo-failure-cases] failure case 2: insufficient allowance..."
cast send "$USDC_ADDRESS" \
  "approve(address,uint256)(bool)" \
  "$GATEWAY_ADDRESS" 0 \
  --rpc-url "$FORK_RPC_LOCAL" \
  --private-key "$AGENT_PRIVKEY" \
  --silent >/dev/null 2>&1

write_config
STDERR_OUT=$("$RMPC_BIN" deposit \
    --config "$TMPDIR_DEMO/rmpc-config.toml" \
    --amount 100000000 \
    --order-id 0x3333333333333333333333333333333333333333333333333333333333333333 \
    2>&1 >/dev/null || true)

if echo "$STDERR_OUT" | grep -qi "ErrInsufficientAllowance\|allowance\|preflight"; then
  ok "failure case 2: insufficient allowance refused"
else
  err "failure case 2: expected ErrInsufficientAllowance refusal, got: $STDERR_OUT"
fi

# Restore allowance.
cast send "$USDC_ADDRESS" \
  "approve(address,uint256)(bool)" \
  "$GATEWAY_ADDRESS" 1000000000 \
  --rpc-url "$FORK_RPC_LOCAL" \
  --private-key "$AGENT_PRIVKEY" \
  --silent >/dev/null 2>&1

# -----------------------------------------------------------------------
# Failure case 3: paused gateway.
# -----------------------------------------------------------------------
echo "[demo-failure-cases] failure case 3: paused gateway..."
cast send "$GATEWAY_ADDRESS" \
  "pause()" \
  --rpc-url "$FORK_RPC_LOCAL" \
  --private-key "$PAUSER_PRIVKEY" \
  --silent >/dev/null 2>&1

write_config
STDERR_OUT=$("$RMPC_BIN" deposit \
    --config "$TMPDIR_DEMO/rmpc-config.toml" \
    --amount 100000000 \
    --order-id 0x4444444444444444444444444444444444444444444444444444444444444444 \
    2>&1 >/dev/null || true)

if echo "$STDERR_OUT" | grep -qi "ErrGatewayPaused\|paused\|preflight"; then
  ok "failure case 3: paused gateway refused"
else
  err "failure case 3: expected ErrGatewayPaused refusal, got: $STDERR_OUT"
fi

# Restore (unpause). unpause() requires ADMIN_ROLE per the gateway contract.
cast send "$GATEWAY_ADDRESS" \
  "unpause()" \
  --rpc-url "$FORK_RPC_LOCAL" \
  --private-key "$ADMIN_PRIVKEY" \
  --silent >/dev/null 2>&1

# -----------------------------------------------------------------------
# Failure case 4: fee cap exceeded (max_fee_per_gas_cap = 1 wei).
# -----------------------------------------------------------------------
echo "[demo-failure-cases] failure case 4: fee cap exceeded..."
write_config "$GATEWAY_RUNTIME_HASH" 1

STDERR_OUT=$("$RMPC_BIN" deposit \
    --config "$TMPDIR_DEMO/rmpc-config.toml" \
    --amount 100000000 \
    --order-id 0x5555555555555555555555555555555555555555555555555555555555555555 \
    2>&1 >/dev/null || true)

if echo "$STDERR_OUT" | grep -qi "ErrFeeCapExceeded\|fee.*cap\|fee cap"; then
  ok "failure case 4: fee cap exceeded refused"
else
  err "failure case 4: expected ErrFeeCapExceeded refusal, got: $STDERR_OUT"
fi

# -----------------------------------------------------------------------
# Failure case 5: code-hash mismatch.
# -----------------------------------------------------------------------
echo "[demo-failure-cases] failure case 5: code-hash mismatch..."
BAD_HASH="0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
write_config "$BAD_HASH" 100000000000

STDERR_OUT=$("$RMPC_BIN" deposit \
    --config "$TMPDIR_DEMO/rmpc-config.toml" \
    --amount 100000000 \
    --order-id 0x6666666666666666666666666666666666666666666666666666666666666666 \
    2>&1 >/dev/null || true)

if echo "$STDERR_OUT" | grep -qi "ErrCodeHashMismatch\|code.*hash\|hash.*mismatch\|preflight"; then
  ok "failure case 5: code-hash mismatch refused"
else
  err "failure case 5: expected ErrCodeHashMismatch refusal, got: $STDERR_OUT"
fi

# -----------------------------------------------------------------------
# Summary.
# -----------------------------------------------------------------------
echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "[demo-failure-cases] all 5 failure cases demonstrated correctly."
  exit 0
else
  echo "[demo-failure-cases] one or more failure cases did not produce the expected refusal." >&2
  exit 1
fi
