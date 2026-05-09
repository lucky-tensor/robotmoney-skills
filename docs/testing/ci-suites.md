# CI Suite Inventory

Each section is one GitHub Actions workflow file. Steps are listed in
execution order as they appear (or should appear) in the job.

The CI job has no special devnet setup step — the test suite itself starts
and tears down the Docker Compose stack whenever it needs a clean slate.

## Environment key

| Symbol | Meaning |
|--------|---------|
| `devnet` | Geth + Lighthouse Docker Compose stack (`testing/ethereum-testnet/config/`). Lifecycle owned by the test code. |
| `anvil` | In-process Anvil EVM. No Docker. |
| `fork` | Anvil forked from a pinned mainnet block via `RMPC_FORK_RPC_URL`. Skips loudly when the secret is absent. |
| `none` | No chain. Static analysis, pure unit tests, doc checks. |

---

## Suites

### 1–2. Smart contract unit tests, invariant tests, and coverage gate
**File:** `.github/workflows/forge-coverage.yml` — _exists_
**Environment:** `anvil`
**Trigger paths:** `contracts/**`, `foundry.toml`

**Steps:**
1. Checkout repository
2. Install Foundry toolchain
3. Cache Foundry build artifacts (`cache/`, `out/`)
4. `forge fmt --check`
5. `forge build`
6. `forge test` — unit tests: every public function, access control boundary, revert path, event emission, ERC-4626 rounding invariant
7. `forge test` with fuzzer enabled — invariant tests: share accounting, per-agent cap sequences, deposit monotonicity, reentrancy under malicious stub, pause invariant
8. `forge coverage` with `check_gateway_coverage.py` — enforces branch-coverage gate on `RobotMoneyGateway`

---

### 3. Smart contract static analysis
**File:** `.github/workflows/solidity-static.yml` — _planned_
**Environment:** `none`
**Trigger paths:** `contracts/**`

**Steps:**
1. Checkout repository
2. Install Python + Slither
3. Install Foundry toolchain (for contract compilation)
4. `forge build` — produce artifacts for Slither
5. `slither .` — standard detector set (reentrancy, uninitialized storage, dangerous delegatecall, tx.origin, unchecked low-level calls)
6. Dependency audit — check imported OpenZeppelin and Aave interface versions against known-vulnerable releases

---

### 4. Fork integration tests (protocol adapters)
**File:** `.github/workflows/fork-e2e.yml` — _exists_
**Environment:** `fork`
**Trigger paths:** `testing/fork-e2e-rust/**`

Two jobs: `pr-smoke` runs the fast subset on every PR; `full-suite` runs all scenarios on push to `main` and `workflow_dispatch`.

**Steps (both jobs):**
1. Checkout repository
2. Install Rust toolchain + clippy
3. Install Foundry toolchain
4. Cargo cache
5. `cargo fmt --check` + `cargo clippy`
6. `cargo test --no-run` — build test binaries
7. _(pr-smoke only)_ `abi_address_sanity` + `vault_deposit_redeem_smoke` — fast subset
8. _(full-suite only)_ All scenarios: `abi_address_sanity`, `vault_deposit_redeem_smoke`, `dex_route_smoke`, `failure_surface_smoke`, `gas_estimate_reality_check`, plus all `rmpc_get_*` fork tests

---

### 5. Rust client unit tests
**File:** `.github/workflows/rmpc-unit.yml` — _planned_
**Environment:** `none`
**Trigger paths:** `clients/rust-payment-client/**`

**Steps:**
1. Checkout repository
2. Install Rust toolchain + clippy
3. Cargo cache
4. `cargo fmt --check`
5. `cargo clippy --all-targets -- -D warnings`
6. `cargo test --lib` — calldata builder output, preflight rejection cases, nonce management logic, fee policy guard, JSON output schema conformance, config parsing

---

### 6. Rust client integration tests
**File:** `.github/workflows/e2e-rust-ci.yml` — _exists_
**Environment:** `devnet` (Geth + Lighthouse)
**Trigger paths:** `clients/rust-payment-client/**`, `testing/ethereum-testnet/e2e-rust/**`, `contracts/**`

Two jobs: `geth-tests` (devnet-backed) and `nonce-race-stress` (no chain).

**Steps — `geth-tests` job:**
1. Checkout repository
2. Verify Docker is available
3. Install Rust toolchain + clippy
4. Install Foundry toolchain
5. Cargo cache
6. `cargo fmt --check` + `cargo clippy` on both `rmpc` and `e2e-rust` crates
7. Pre-pull Docker images
8. `cargo build --release` — produce `rmpc` binary
9. `cargo test --test skill_docs_parity` — skill-package parity (no Docker)
10. `cargo test --test dapp_toml_roundtrip` — dApp TOML round-trip (no Docker)
11. `cargo test --release --test smoke --test-threads=1` — devnet boots inside test
12. `docker compose down -v` — explicit teardown between binaries
13. `cargo test --release --test scenarios --test-threads=1` — all policy/failure scenarios
14. `docker compose down -v`
15. `cargo test --release --test window_cap --test-threads=1`
16. `docker compose down -v` (always, on failure)

**Steps — `nonce-race-stress` job:**
1. Checkout repository
2. Install Rust toolchain
3. Cargo cache
4. `bash .github/scripts/stress_nonce_race.sh` — runs the race test 100× in-process; no chain

---

### 7. Explorer indexer tests
**File:** `.github/workflows/explorer-indexer.yml` — _exists_ (devnet migration planned)
**Environment:** `devnet`
**Trigger paths:** `services/explorer-indexer/**`, `testing/explorer-indexer/**`

**Steps:**
1. Checkout repository
2. Verify Docker is available
3. Install Rust toolchain + clippy
4. Cargo cache
5. `cargo fmt --check` + `cargo clippy`
6. `cargo test --no-run`
7. `cargo test --test migrations` — migration idempotency (Postgres testcontainer started by the test)
8. `cargo test --test idempotency` — block ingestion against known deposit events; double-count guard
9. `cargo test --test rpc_failure` — RPC failure recovery; reconnect and resume from last confirmed block
10. `cargo test --test fork_indexer` — reorg handling (orphaned-block row removal) and finality-gated indexing against devnet (requires real Geth + Lighthouse fork choice)

> **Note:** Steps 7–9 currently use a Postgres testcontainer + Anvil fork.
> Step 10 is the devnet-dependent target; migration is planned.

---

### 8. dApp unit tests
**File:** `.github/workflows/dapp.yml` — _exists_ (`lint-unit` job)
**Environment:** `none`
**Trigger paths:** `clients/dapp/**`

**Steps:**
1. Checkout repository
2. Setup pnpm + Node 22
3. `pnpm install --frozen-lockfile`
4. `pnpm fmt` — Prettier check
5. `pnpm lint` — ESLint
6. `pnpm exec tsc -b` — TypeScript type check
7. `pnpm test` — Vitest: component rendering, browser-side key generation, credential boundary (no key material in DOM), form validation
8. `pnpm build` — verify production build succeeds

---

### 9. dApp E2E tests
**File:** `.github/workflows/dapp.yml` — _exists_ (e2e jobs); devnet migration planned
**Environment:** `devnet`
**Trigger paths:** `clients/dapp/**`, `contracts/**`
**Depends on:** suite 8 (`lint-unit` job must pass first)

Three parallel jobs after `lint-unit`: `e2e`, `e2e-history-pane`, `fork-roundtrip`.

**Steps — `e2e` job:**
1. Checkout repository
2. Setup pnpm + Node 22
3. Install Foundry toolchain
4. `pnpm install --frozen-lockfile`
5. `pnpm test:e2e:install` — Playwright browser binaries
6. Start devnet sidecar (test suite owns lifecycle)
7. `pnpm test:e2e` — wallet connect → vault state display, deposit golden path, admin actions (register agent, set cap, pause, revoke), transaction error display, no key-material-in-DOM scan
8. Upload Playwright report artifact on failure

**Steps — `e2e-history-pane` job:**
1–5. Same as `e2e`
6. Start devnet sidecar
7. `pnpm test:e2e tests/e2e/history-pane.spec.ts` with `VITE_HISTORY_PANE=true` — history pane renders deposit rows from stubbed explorer API
8. Upload Playwright report artifact on failure

**Steps — `fork-roundtrip` job:**
1. Checkout repository
2. Setup pnpm + Node 22 + Rust + Foundry
3. `pnpm install --frozen-lockfile`
4. `pnpm exec playwright install --with-deps chromium`
5. `bash clients/dapp/scripts/run-fork-roundtrip.sh` — deploys gateway on local devnet, mints agent keystore, dApp authorizes agent, `rmpc self-check` asserts `ErrAgentNotAuthorized` after revoke and exit 0 after re-authorize
6. Upload Playwright report artifact on failure

> **Note:** The existing jobs use a local Anvil sidecar. Migration to the
> devnet is the intended target shape.

---

### 10. OpenCode integration tests
**File:** `.github/workflows/opencode-plugin-smoke.yml` — _exists_; `.github/workflows/opencode-walkthrough.yml` — _exists_; `.github/workflows/opencode-headless-deposit.yml` — _exists_; `.github/workflows/opencode-headless-read.yml` — _exists_
**Environment:** `devnet` (plugin smoke: `none`)
**Trigger:** Plugin smoke on every PR; walkthrough on every PR; headless tests nightly + `workflow_dispatch` (require `ANTHROPIC_API_KEY`)

**Steps — plugin smoke (`opencode-plugin-smoke.yml`):**
1. Checkout repository
2. Install OpenCode at pinned version
3. Verify `plugin.json` parses as valid JSON
4. Verify `SKILL.md` frontmatter is present and well-formed
5. Verify all `references/*.md` links resolve
6. `opencode --version` + `opencode run --help` — binary is functional without a model key

**Steps — walkthrough offline checks (`opencode-walkthrough.yml`, `offline-checks` job):**
1. Checkout repository
2. Install Rust toolchain + clippy
3. Cargo cache
4. `cargo fmt --check` + `cargo clippy`
5. `cargo test --test walkthrough_parity` — doc parity between `opencode-readonly-fork.md` and installed harness config
6. `cargo test --test config_template_parses` — TOML config template parses through rmpc's real config loader
7. `cargo test --test refusal_walkthrough` — **safety step**: prompt injection refusal, mainnet gate, out-of-policy amount refusal, unknown tool refusal, secret handling, read-only isolation (offline; no chain)

**Steps — walkthrough fork inspection (`opencode-walkthrough.yml`, `fork-check` job):**
1. Checkout repository
2. Install Rust + Foundry toolchain
3. Cargo cache
4. `cargo test --test read_only_walkthrough` — rmpc envelope contract against devnet (skip-cleans without `RMPC_FORK_RPC_URL`)

**Steps — headless deposit (`opencode-headless-deposit.yml`):**
1. Checkout repository
2. Install OpenCode at pinned version + Rust + Foundry
3. Deploy `MockUSDC` + `MockVault` + `RobotMoneyGateway` via `Deploy.s.sol` on devnet
4. Generate fresh agent EOA; write keystore via `rmpc-keystore-import`
5. Fund agent ETH balance via `anvil_setBalance`; set USDC approval via impersonation
6. **Safety step**: run refusal transcript assertions (prompt injection, mainnet gate, out-of-policy amount) — no model key required
7. `opencode run <deposit-prompt> --format json` against devnet
8. `assert_headless_deposit_transcript.py` — asserts tool-call order (get-vault → get-agent → get-balance → get-allowance → self-check → deposit), `final-report.json` outcome, tx_hash non-null hex

**Steps — headless read (`opencode-headless-read.yml`):**
1. Checkout repository
2. Install OpenCode at pinned version + Rust + Foundry
3. Deploy contracts + fund agent on devnet
4. **Safety step**: read-only isolation assertions — agent in read-only config cannot invoke state-changing tools
5. `opencode run <read-prompt> --format json` against devnet
6. `assert_headless_read_transcript.py` — asserts vault state, balance, and allowance queries match JSON schema

> **Note:** The existing headless workflows use an Anvil fork. Migration
> to the devnet is the intended target shape.

---

### 11. OpenClaw integration tests
**File:** `.github/workflows/openclaw-config.yml` — _exists_
**Environment:** `devnet`
**Trigger paths:** `testing/openclaw-config/**`, `plugins/robotmoney-cli/**`, `docs/walkthroughs/openclaw-config.md`

**Steps:**
1. Checkout repository
2. Install Rust toolchain
3. Cargo cache
4. `shellcheck -x testing/openclaw-config/*.sh`
5. `cargo build --manifest-path clients/rust-payment-client/Cargo.toml --bin rmpc`
6. `bash test_mainnet_gate.sh` — **safety step**: OpenClaw configured for fork cannot broadcast against mainnet RPC
7. `bash test_secret_handling.sh` — **safety step**: key material, RPC URLs with embedded API keys, and mnemonic phrases never appear in conversation or logs
8. `bash test_doc_parity.sh` — walkthrough parity between `openclaw-config.md` and installed harness config
9. `bash test_long_running.sh` — deposit walkthrough driven through OpenClaw runtime against devnet; same transcript assertions as the OpenCode deposit suite (skip-cleans without `RMPC_FORK_RPC_URL`)
10. Upload `artifacts/long-running/outcome.txt` artifact; assert it is well-formed (`outcome=pass|skipped|fail`, `reason=` present)

---

### 12. Cross-cutting checks
**File:** `.github/workflows/docs-validators.yml` — _exists_; `.github/workflows/explorer-schema.yml` — _exists_
**Environment:** `none`
**Trigger:** All PRs (no `paths:` filter — these catch drift introduced anywhere)

**Steps — `docs-validators.yml`:**
1. Checkout repository
2. Install Python
3. `check_browser_keygen_adr.py` — browser keygen ADR file exists with expected structure
4. `check_dapp_credential_adr.py` — dApp credential ADR compliance
5. `check_demo_runbook.py` — demo runbook headings and required sections present
6. `check_explorer_adr.py` — explorer schema ADR compliance
7. `check_gateway_coverage.py` — gateway coverage report present and above threshold
8. `check_source_doc_reconciliation.py` — source-doc reconciliation file up to date

**Steps — `explorer-schema.yml`:**
1. Checkout repository
2. Install Python
3. `check_explorer_migrations.py` — single-canonical-home invariant: migration files exist only in `services/explorer-indexer/migrations/`, no duplicates elsewhere

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
| 8 | `dapp.yml` (`lint-unit` job) | exists | `none` |
| 9 | `dapp.yml` (e2e jobs) | exists → devnet migration | `devnet` |
| 10 | `opencode-plugin-smoke.yml`, `opencode-walkthrough.yml`, `opencode-headless-deposit.yml`, `opencode-headless-read.yml` | exists → devnet migration | `devnet` |
| 11 | `openclaw-config.yml` | exists → devnet migration | `devnet` |
| 12 | `docs-validators.yml`, `explorer-schema.yml` | exists | `none` |
