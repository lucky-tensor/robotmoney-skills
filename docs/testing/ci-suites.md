# CI Suite Inventory

Each row is a GitHub Actions workflow file. The suite column links to the
file; the environment column says what backing infrastructure the test suite
itself starts (the CI job has no special setup step — lifecycle is owned by
the test code).

## Environment key

| Symbol | Meaning |
|--------|---------|
| `devnet` | Geth + Lighthouse Docker Compose stack (`testing/ethereum-testnet/config/`). Suite starts and tears down the stack as needed for a clean slate. |
| `anvil` | In-process Anvil EVM. No Docker. |
| `fork` | Anvil forked from a pinned mainnet block via `RMPC_FORK_RPC_URL`. Skips loudly when the secret is absent. |
| `none` | No chain. Static analysis, pure unit tests, doc checks. |

---

## Suites

### 1. Smart contract unit tests + coverage gate
**File:** `.github/workflows/forge-coverage.yml` — _exists_
**Environment:** `anvil` (Foundry in-process)
**Trigger paths:** `contracts/**`, `foundry.toml`

Covers every public function, access control boundary, revert path, event
emission, and ERC-4626 rounding invariant. Also enforces the branch-coverage
gate on `RobotMoneyGateway`.

---

### 2. Smart contract property / invariant tests
**File:** `.github/workflows/forge-coverage.yml` — _exists_ (same job as suite 1)
**Environment:** `anvil`

Foundry fuzzer: share accounting invariant, per-agent cap across arbitrary
deposit sequences, deposit monotonicity, no-reentrancy under malicious stub,
pause invariant.

---

### 3. Smart contract static analysis
**File:** `.github/workflows/solidity-static.yml` — _planned_
**Environment:** `none`
**Trigger paths:** `contracts/**`

Slither standard detector set. Dependency audit against known-vulnerable
OpenZeppelin / Aave interface versions.

---

### 4. Fork integration tests (protocol adapters)
**File:** `.github/workflows/fork-e2e.yml` — _exists_
**Environment:** `fork`
**Trigger paths:** `testing/fork-e2e-rust/**`

Aave V3, Compound V3 (Comet), and Morpho adapter deposit/accounting against a
pinned mainnet fork. ABI/address sanity at the pinned block. Adapter failure
mode propagation. Two jobs: `pr-smoke` (fast subset on every PR) and
`full-suite` (all scenarios on push to `main` and `workflow_dispatch`).

---

### 5. Rust client unit tests
**File:** `.github/workflows/rmpc-unit.yml` — _planned_
**Environment:** `none`
**Trigger paths:** `clients/rust-payment-client/**`

Calldata builder output, preflight rejection cases, nonce management logic,
fee policy guard, JSON output schema conformance, config parsing. Pure
`cargo test` — no chain, no Docker.

---

### 6. Rust client integration tests
**File:** `.github/workflows/e2e-rust-ci.yml` — _exists_
**Environment:** `devnet` (Geth + Lighthouse)
**Trigger paths:** `clients/rust-payment-client/**`, `testing/ethereum-testnet/e2e-rust/**`, `contracts/**`

Happy-path deposit, all failure/policy scenarios, idempotency, dapp TOML
round-trip, skill-package parity. The nonce race stress job (`nonce-race-stress`)
runs the race test 100× against an in-process harness — no chain required for
that job.

---

### 7. Explorer indexer tests
**File:** `.github/workflows/explorer-indexer.yml` — _exists_ (devnet migration planned)
**Environment:** `devnet`
**Trigger paths:** `services/explorer-indexer/**`, `testing/explorer-indexer/**`

Migration idempotency, block ingestion against known deposit events, reorg
handling (orphaned-block row removal), finality-gated indexing, RPC failure
recovery. Reorg and finality tests require the real Geth + Lighthouse fork
choice; Anvil cannot produce competing forks.

> **Note:** The existing workflow currently uses a Postgres testcontainer +
> Anvil fork for some jobs. Migration to devnet is the intended target shape.

---

### 8. dApp unit tests
**File:** `.github/workflows/dapp.yml` — _exists_ (lint-unit job)
**Environment:** `none`
**Trigger paths:** `clients/dapp/**`

Component rendering, browser-side key generation correctness, credential
boundary (no key material in DOM or console), form validation. Vitest. Runs
before the E2E jobs.

---

### 9. dApp E2E tests
**File:** `.github/workflows/dapp.yml` — _exists_ (e2e jobs); devnet migration planned
**Environment:** `devnet`
**Trigger paths:** `clients/dapp/**`, `contracts/**`

Wallet connect → vault state display, deposit golden path, admin actions
(register agent, set cap, pause, revoke), transaction error display, no
key-material-in-DOM scan. Playwright. Includes history-pane flag variant and
dapp+rmpc fork-roundtrip job.

> **Note:** The existing E2E jobs use a local Anvil sidecar. Migration to
> the devnet is the intended target shape.

---

### 10. OpenCode integration tests
**File:** `.github/workflows/opencode-walkthrough.yml` — _exists_; `.github/workflows/opencode-headless-deposit.yml` — _exists_; `.github/workflows/opencode-headless-read.yml` — _exists_; `.github/workflows/opencode-plugin-smoke.yml` — _exists_
**Environment:** `devnet`
**Trigger:** Nightly schedule + `workflow_dispatch` (requires `ANTHROPIC_API_KEY`); plugin smoke runs on every PR without a key

Integration tests for manually driven OpenCode sessions. Workflow steps:

1. **Plugin smoke** — structural validity (plugin.json, SKILL.md frontmatter, reference links resolve) without a model key.
2. **Safety step** — prompt injection refusal, mainnet gate enforcement, out-of-policy amount refusal, unknown tool refusal, secret handling (key material never echoed), read-only isolation.
3. **Deposit walkthrough** — transcript asserts correct tool-call order (get-vault → get-agent → get-balance → get-allowance → self-check → deposit) and `final-report.json` outcome.
4. **Read walkthrough** — vault state, balance, and allowance queries match schema.
5. **Failure walkthrough** — policy violation produces structured refusal with no retry loop.

> **Note:** The existing headless-deposit and headless-read workflows use an
> Anvil fork. Migration to the devnet is the intended target shape.

---

### 11. OpenClaw integration tests
**File:** `.github/workflows/openclaw-config.yml` — _exists_
**Environment:** `devnet`
**Trigger paths:** `testing/openclaw-config/**`, `plugins/robotmoney-cli/**`, `docs/walkthroughs/openclaw-config.md`

Integration tests for the OpenClaw agent runtime. Workflow steps:

1. **Safety step** — mainnet gate enforcement, secret handling, out-of-policy refusal, long-running task isolation.
2. **Walkthrough parity** — doc parity between `openclaw-config.md` and the installed harness config.
3. **Deposit walkthrough** — same transcript assertions as the OpenCode suite, driven through the OpenClaw runtime instead.

---

### 12. Cross-cutting checks
**File:** `.github/workflows/docs-validators.yml` — _exists_; `.github/workflows/explorer-schema.yml` — _exists_
**Environment:** `none`
**Trigger:** All PRs (no `paths:` filter — these catch drift introduced anywhere)

ADR compliance (every file named in a decision record exists with expected
structure), coverage gate (gateway contract), lint/format (`clippy`,
`rustfmt`, ESLint, Prettier), dependency audit (`cargo audit`, `pnpm audit`),
no-secrets scan (private key patterns, mnemonic word lists, API key shapes),
explorer schema single-canonical-home invariant.

---

## Summary

| # | Workflow file | Status | Environment |
|---|---------------|--------|-------------|
| 1–2 | `forge-coverage.yml` | exists | `anvil` |
| 3 | `solidity-static.yml` | planned | `none` |
| 4 | `fork-e2e.yml` | exists | `fork` |
| 5 | `rmpc-unit.yml` | planned | `none` |
| 6 | `e2e-rust-ci.yml` | exists | `devnet` |
| 7 | `explorer-indexer.yml` | exists → devnet migration | `devnet` |
| 8 | `dapp.yml` (lint-unit job) | exists | `none` |
| 9 | `dapp.yml` (e2e jobs) | exists → devnet migration | `devnet` |
| 10 | `opencode-walkthrough.yml`, `opencode-headless-deposit.yml`, `opencode-headless-read.yml`, `opencode-plugin-smoke.yml` | exists → devnet migration | `devnet` |
| 11 | `openclaw-config.yml` | exists → devnet migration | `devnet` |
| 12 | `docs-validators.yml`, `explorer-schema.yml` | exists | `none` |
