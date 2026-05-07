# OpenClaw E2E Demo Runbook

> **Canonical:** `docs/implementation-plan.md` §13 (Phase 7 — OpenClaw E2E Demo).
> **Issue:** #116.
>
> This runbook reproduces the full autonomous-agent demo from a clean
> checkout. It covers fork setup, gateway deployment, agent key creation,
> skill loading, the OpenClaw task prompt, artifact paths, and per-failure-case
> toggle commands.
>
> The demo does **not** require the Phase 5 explorer API or the Phase 6
> human dapp. All reads use direct JSON-RPC via `rmpc get-*` subcommands.

---

## Prerequisites

| Tool | Version tested | Install |
|---|---|---|
| `git` | any | system |
| `cargo` / Rust stable | 1.77+ | https://rustup.rs |
| `forge` + `anvil` (Foundry) | nightly-2024-05-01 or newer stable | https://getfoundry.sh |
| `cast` | bundled with Foundry | — |
| `jq` | 1.6+ | system |

A live Base mainnet archive RPC endpoint is required for the fork. The
URL must be set via `RMPC_FORK_RPC_URL` (see §1). The demo never reads
from this endpoint at run time — it is only used by `anvil` to snapshot
chain state.

---

## 1. Fork setup

```bash
# Clone and enter the repo.
git clone https://github.com/lucky-tensor/robotmoney-skills.git
cd robotmoney-skills

# Set your archive RPC URL. Alchemy / Infura / QuickNode work; the URL
# must support eth_getStorageAt and debug_traceCall at the pin block.
export RMPC_FORK_RPC_URL="https://base-mainnet.g.alchemy.com/v2/YOUR_KEY"

# Pin block (refresh monthly per ADR §3.2; this pin was valid 2026-05-07).
export RMPC_FORK_BLOCK=29800000

# Boot the Anvil fork in the background. The fork-config artifact at
# demo/fork-config.toml documents the same parameters.
anvil \
  --fork-url  "$RMPC_FORK_RPC_URL" \
  --fork-block-number "$RMPC_FORK_BLOCK" \
  --chain-id 8453 \
  --port 8545 \
  &
ANVIL_PID=$!
sleep 2   # wait for anvil to come up

# Verify the fork is live and at the correct chain id.
cast chain-id --rpc-url http://127.0.0.1:8545
# Expected output: 8453
```

The pinned block metadata artifact is at
[`demo/fork-metadata.json`](../../demo/fork-metadata.json).

---

## 2. Build rmpc

```bash
cargo build \
  --manifest-path clients/rust-payment-client/Cargo.toml \
  --bin rmpc

# Alias for the rest of this runbook.
RMPC="./clients/rust-payment-client/target/debug/rmpc"
$RMPC --help
```

---

## 3. Create ephemeral keys

The demo uses three distinct EOAs — admin, pauser, agent — to satisfy the
gateway's role-separation invariant. Use `cast wallet new` (Foundry) or any
other key generator. The private keys must never be reused outside the fork.

```bash
# Generate three throwaway keypairs.
cast wallet new --json > /tmp/demo-admin.json
cast wallet new --json > /tmp/demo-pauser.json
cast wallet new --json > /tmp/demo-agent.json

# Export addresses and private keys.
export ADMIN_ADDRESS=$(jq -r .address /tmp/demo-admin.json)
export ADMIN_PRIVKEY=$(jq -r .private_key /tmp/demo-admin.json)

export PAUSER_ADDRESS=$(jq -r .address /tmp/demo-pauser.json)
export PAUSER_PRIVKEY=$(jq -r .private_key /tmp/demo-pauser.json)

export AGENT_ADDRESS=$(jq -r .address /tmp/demo-agent.json)
export AGENT_PRIVKEY=$(jq -r .private_key /tmp/demo-agent.json)

# The share-receiver can be any address; use the admin for simplicity.
export SHARE_RECEIVER_ADDRESS="$ADMIN_ADDRESS"

# Fund all three with ETH via anvil's cheatcode.
cast rpc anvil_setBalance "$ADMIN_ADDRESS"  0x56BC75E2D63100000 \
  --rpc-url http://127.0.0.1:8545
cast rpc anvil_setBalance "$PAUSER_ADDRESS" 0x56BC75E2D63100000 \
  --rpc-url http://127.0.0.1:8545
cast rpc anvil_setBalance "$AGENT_ADDRESS"  0x56BC75E2D63100000 \
  --rpc-url http://127.0.0.1:8545
```

---

## 4. Deploy gateway stack

The deploy script creates MockUSDC, MockVault, and RobotMoneyGateway, grants
the agent AGENT_ROLE, and mints test USDC to the agent.

```bash
# Record output path.
export DEPLOYMENT_OUT="/tmp/demo-deployment.json"

forge script contracts/script/Deploy.s.sol:Deploy \
  --rpc-url http://127.0.0.1:8545 \
  --private-key "$ADMIN_PRIVKEY" \
  --broadcast \
  --env ADMIN_ADDRESS="$ADMIN_ADDRESS" \
  --env PAUSER_ADDRESS="$PAUSER_ADDRESS" \
  --env AGENT_ADDRESS="$AGENT_ADDRESS" \
  --env SHARE_RECEIVER_ADDRESS="$SHARE_RECEIVER_ADDRESS" \
  --env DEPLOYMENT_OUT="$DEPLOYMENT_OUT"

# Parse deployed addresses.
export GATEWAY_ADDRESS=$(jq -r .gateway "$DEPLOYMENT_OUT")
export USDC_ADDRESS=$(jq -r .usdc "$DEPLOYMENT_OUT")
export VAULT_ADDRESS=$(jq -r .vault "$DEPLOYMENT_OUT")
export GATEWAY_RUNTIME_HASH=$(jq -r .gateway_runtime_hash "$DEPLOYMENT_OUT")

echo "Gateway : $GATEWAY_ADDRESS"
echo "USDC    : $USDC_ADDRESS"
echo "Vault   : $VAULT_ADDRESS"
echo "Hash    : $GATEWAY_RUNTIME_HASH"
```

---

## 5. Create the rmpc config

```bash
# Create an encrypted keystore for the agent key.
KEYSTORE_PATH="/tmp/demo-agent-keystore.json"
RMPC_SIGNER_PASSPHRASE="demo-passphrase-ephemeral"
echo "$AGENT_PRIVKEY" | cast wallet import \
  --private-key-stdin \
  --password "$RMPC_SIGNER_PASSPHRASE" \
  "$KEYSTORE_PATH"

# Write the operator config.
cat > /tmp/demo-rmpc-config.toml <<TOML
# OpenClaw E2E Demo — rmpc operator config
# Canonical: docs/technical/demo-runbook.md §5
# Generated for fork block $RMPC_FORK_BLOCK on chain 8453.

chain_id             = 8453
rpc_url              = "http://127.0.0.1:8545"
gateway_address      = "$GATEWAY_ADDRESS"
usdc_address         = "$USDC_ADDRESS"
vault_address        = "$VAULT_ADDRESS"
gateway_runtime_hash = "$GATEWAY_RUNTIME_HASH"
max_fee_per_gas_cap  = 100000000000

[signer]
allow_software_fallback = true
keystore_path           = "$KEYSTORE_PATH"

state_dir = "/tmp/demo-rmpc-state"
TOML

mkdir -p /tmp/demo-rmpc-state
export RMPC_CONFIG=/tmp/demo-rmpc-config.toml
```

The template config (without runtime addresses) is at
[`demo/rmpc-config-template.toml`](../../demo/rmpc-config-template.toml).

---

## 6. Approve USDC allowance for the gateway

The agent must approve the gateway to pull USDC before a deposit is
permitted. This is an operator action, not an agent action (the agent
never issues ERC-20 approvals per `references/safety.md`).

```bash
# Approve 1000 USDC (1_000_000_000 in 6-decimal units).
cast send "$USDC_ADDRESS" \
  "approve(address,uint256)(bool)" \
  "$GATEWAY_ADDRESS" 1000000000 \
  --rpc-url http://127.0.0.1:8545 \
  --private-key "$AGENT_PRIVKEY"
```

---

## 7. OpenClaw task — verbatim prompt

Run this prompt in OpenClaw with the Robot Money skill loaded
(see §8 for skill loading). The prompt is bounded and produces a
structured final report.

```
Monitor vault status, verify the agent is authorized and funded,
deposit exactly 100 USDC (100000000 in 6-decimal units) for order
0x1111111111111111111111111111111111111111111111111111111111111111
when all preflight checks pass, then report the tx hash, deposit id,
vault position (shares minted), and block number in a JSON object.
```

Expected agent command trace (6 required behaviors):

1. **Skill loaded / rmpc selected** — agent invokes `rmpc get-vault`,
   confirming it selected the `robotmoney-cli` skill.
2. **Direct chain reads before any write** — agent runs
   `get-vault`, `get-gateway`, `get-agent`, `get-balance`,
   `get-allowance` and `self-check` before calling `deposit`.
3. **Preflight pass / refusal when a check fails** — agent refuses if
   any read returns a failing state.
4. **Successful guarded deposit** — `rmpc deposit` returns exit 0 and
   a JSON envelope containing `paymentId` and `txHash`.
5. **Record tx hash, deposit id, vault position, block number** — agent
   runs `rmpc status --payment-id <id>` and `rmpc get-deposit`.
6. **Concise final report** — agent emits a JSON summary.

---

## 8. Skill loading into OpenClaw

Point OpenClaw at the skill package directory:

```bash
# The skill package is at plugins/robotmoney-cli/
# in this repo. The snapshot used for the demo run is
# preserved at demo/skill-snapshot/ (see that directory's README).

SKILL_DIR="$(pwd)/plugins/robotmoney-cli"
RMPC_BIN="$(pwd)/clients/rust-payment-client/target/debug/rmpc"
```

OpenClaw harness wrapper (for bounded monitor mode):

```bash
RMPC_CONFIG="$RMPC_CONFIG" \
RMPC_NETWORK=fork \
RMPC_MONITOR_COMMAND=get-vault \
RMPC_MONITOR_ITERATIONS=3 \
RMPC_MONITOR_INTERVAL_SECS=1 \
RMPC_BIN="$RMPC_BIN" \
  bash testing/openclaw-config/openclaw_harness.sh
```

---

## 9. Manual read walkthrough (demo behavior 1–2)

These commands reproduce what OpenClaw runs during the pre-deposit read
phase. They require only `$RMPC_CONFIG` (no passphrase for reads).

```bash
# Vault state (behavior 1: agent selects rmpc / reads chain directly).
$RMPC get-vault --config "$RMPC_CONFIG" --pretty

# Gateway state.
$RMPC get-gateway --config "$RMPC_CONFIG" --pretty

# Agent authorization + window usage.
$RMPC get-agent --config "$RMPC_CONFIG" --agent "$AGENT_ADDRESS" --pretty

# Agent role membership.
$RMPC get-roles --config "$RMPC_CONFIG" --agent "$AGENT_ADDRESS" --pretty

# USDC balance.
$RMPC get-balance --config "$RMPC_CONFIG" --address "$AGENT_ADDRESS" --pretty

# USDC allowance for the gateway.
$RMPC get-allowance --config "$RMPC_CONFIG" \
  --owner "$AGENT_ADDRESS" --spender "$GATEWAY_ADDRESS" --pretty

# Signer self-check (behavior 2: runs before any write).
export RMPC_SIGNER_PASSPHRASE="demo-passphrase-ephemeral"
$RMPC self-check --config "$RMPC_CONFIG" --pretty
```

Captured example output is at [`demo/artifacts/read-trace.json`](../../demo/artifacts/read-trace.json).

---

## 10. Happy-path deposit (demo behavior 3–6)

```bash
export RMPC_SIGNER_PASSPHRASE="demo-passphrase-ephemeral"

$RMPC deposit \
  --config "$RMPC_CONFIG" \
  --amount 100000000 \
  --order-id 0x1111111111111111111111111111111111111111111111111111111111111111 \
  --pretty \
  | tee /tmp/demo-deposit-result.json

# Extract the payment id.
PAYMENT_ID=$(jq -r .paymentId /tmp/demo-deposit-result.json)
TX_HASH=$(jq -r .txHash /tmp/demo-deposit-result.json)

# Confirm on-chain record.
$RMPC status \
  --config "$RMPC_CONFIG" \
  --payment-id "$PAYMENT_ID" \
  --pretty \
  | tee /tmp/demo-status-result.json

$RMPC get-deposit \
  --config "$RMPC_CONFIG" \
  --deposit-id "$PAYMENT_ID" \
  --pretty \
  | tee /tmp/demo-deposit-record.json
```

Captured output is at [`demo/artifacts/deposit-trace.json`](../../demo/artifacts/deposit-trace.json)
and [`demo/artifacts/final-report.json`](../../demo/artifacts/final-report.json).

---

## 11. Failure-case toggle commands

Each of the five failure cases is demonstrable by running one command
before the deposit attempt, then running `rmpc deposit` to observe the
refusal.

### 11.1 Unauthorized agent (revoke AGENT_ROLE)

```bash
# Revoke the agent's authorization (gateway's revokeAgent, ADMIN_ROLE required).
cast send "$GATEWAY_ADDRESS" \
  "revokeAgent(address)()" \
  "$AGENT_ADDRESS" \
  --rpc-url http://127.0.0.1:8545 \
  --private-key "$ADMIN_PRIVKEY"

# Deposit attempt — expect ErrAgentNotAuthorized.
$RMPC deposit \
  --config "$RMPC_CONFIG" \
  --amount 100000000 \
  --order-id 0x2222222222222222222222222222222222222222222222222222222222222222
# exit 1; stderr: {"code":"ErrAgentNotAuthorized",...}

# Restore (re-authorize for subsequent demos).
# Use the gateway's authorizeAgent(address,AgentPolicy) via forge script
# or cast with the packed ABI if needed.
```

### 11.2 Insufficient allowance (zero USDC allowance)

```bash
# Zero out the allowance.
cast send "$USDC_ADDRESS" \
  "approve(address,uint256)(bool)" \
  "$GATEWAY_ADDRESS" 0 \
  --rpc-url http://127.0.0.1:8545 \
  --private-key "$AGENT_PRIVKEY"

# Deposit attempt — expect ErrInsufficientAllowance.
$RMPC deposit \
  --config "$RMPC_CONFIG" \
  --amount 100000000 \
  --order-id 0x3333333333333333333333333333333333333333333333333333333333333333
# exit 1; stderr: {"code":"ErrInsufficientAllowance",...}

# Restore allowance.
cast send "$USDC_ADDRESS" \
  "approve(address,uint256)(bool)" \
  "$GATEWAY_ADDRESS" 1000000000 \
  --rpc-url http://127.0.0.1:8545 \
  --private-key "$AGENT_PRIVKEY"
```

### 11.3 Paused gateway

```bash
# Pause the gateway (PAUSER_ROLE is PAUSER_ADDRESS).
cast send "$GATEWAY_ADDRESS" \
  "pause()()" \
  --rpc-url http://127.0.0.1:8545 \
  --private-key "$PAUSER_PRIVKEY"

# Read confirms paused = true.
$RMPC get-gateway --config "$RMPC_CONFIG" --pretty
# "paused": true

# Deposit attempt — expect ErrGatewayPaused.
$RMPC deposit \
  --config "$RMPC_CONFIG" \
  --amount 100000000 \
  --order-id 0x4444444444444444444444444444444444444444444444444444444444444444
# exit 1; stderr: {"code":"ErrGatewayPaused",...}

# Restore. unpause() requires ADMIN_ROLE on the gateway (not PAUSER_ROLE).
cast send "$GATEWAY_ADDRESS" \
  "unpause()()" \
  --rpc-url http://127.0.0.1:8545 \
  --private-key "$ADMIN_PRIVKEY"
```

### 11.4 Fee cap exceeded

```bash
# Set max_fee_per_gas_cap to 1 wei (below any real fee).
cat > /tmp/demo-rmpc-config-feecap.toml <<TOML
chain_id             = 8453
rpc_url              = "http://127.0.0.1:8545"
gateway_address      = "$GATEWAY_ADDRESS"
usdc_address         = "$USDC_ADDRESS"
vault_address        = "$VAULT_ADDRESS"
gateway_runtime_hash = "$GATEWAY_RUNTIME_HASH"
max_fee_per_gas_cap  = 1

[signer]
allow_software_fallback = true
keystore_path           = "$KEYSTORE_PATH"

state_dir = "/tmp/demo-rmpc-state"
TOML

# Deposit attempt — expect ErrFeeCapExceeded.
$RMPC deposit \
  --config /tmp/demo-rmpc-config-feecap.toml \
  --amount 100000000 \
  --order-id 0x5555555555555555555555555555555555555555555555555555555555555555
# exit 1; stderr: {"code":"ErrFeeCapExceeded",...}
```

### 11.5 Code-hash mismatch

```bash
# Set a wrong gateway_runtime_hash in the config.
cat > /tmp/demo-rmpc-config-badhash.toml <<TOML
chain_id             = 8453
rpc_url              = "http://127.0.0.1:8545"
gateway_address      = "$GATEWAY_ADDRESS"
usdc_address         = "$USDC_ADDRESS"
vault_address        = "$VAULT_ADDRESS"
gateway_runtime_hash = "0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
max_fee_per_gas_cap  = 100000000000

[signer]
allow_software_fallback = true
keystore_path           = "$KEYSTORE_PATH"

state_dir = "/tmp/demo-rmpc-state"
TOML

# Deposit attempt — expect ErrCodeHashMismatch.
$RMPC deposit \
  --config /tmp/demo-rmpc-config-badhash.toml \
  --amount 100000000 \
  --order-id 0x6666666666666666666666666666666666666666666666666666666666666666
# exit 1; stderr: {"code":"ErrCodeHashMismatch",...}
```

---

## 12. Teardown

```bash
kill "$ANVIL_PID" 2>/dev/null || true
rm -rf /tmp/demo-rmpc-state /tmp/demo-admin.json /tmp/demo-pauser.json \
       /tmp/demo-agent.json /tmp/demo-agent-keystore.json
```

---

## 13. Artifact paths

| Artifact | Path |
|---|---|
| Fork config (Anvil parameters) | `demo/fork-config.toml` |
| Pinned block metadata | `demo/fork-metadata.json` |
| OpenClaw config template | `demo/openclaw-config.toml` |
| rmpc config template (no runtime addrs) | `demo/rmpc-config-template.toml` |
| Skill package snapshot | `demo/skill-snapshot/` |
| Captured read-phase trace | `demo/artifacts/read-trace.json` |
| Captured deposit trace | `demo/artifacts/deposit-trace.json` |
| Captured status / get-deposit output | `demo/artifacts/status-trace.json` |
| Final report | `demo/artifacts/final-report.json` |

---

## 14. What is intentionally not here

- **Phase 5 explorer API.** Not required. All reads use `rmpc get-*`
  direct JSON-RPC subcommands.
- **Phase 6 human dapp.** Not required. Allowance approval and admin
  actions use `cast` commands driven by the operator.
- **Mainnet execution.** Fork only. The `RMPC_ALLOW_MAINNET` toggle is
  deliberately omitted; the harness refuses with exit 10 if someone
  sets `RMPC_NETWORK=mainnet` without the toggle.
