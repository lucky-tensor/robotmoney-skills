# Robot Money — Implementation Plan

> Companion to `docs/architecture.md` and `docs/prd.md`. This plan covers the
> full initiative from foundational infrastructure through production readiness.
> As of May 2026, the application and infrastructure are ~90% complete; the
> remaining work is concentrated in security hardening, release infrastructure,
> full-stack integration, and onboarding documentation.
>
> **Relationship to the product.** Robot Money is a multi-vault ERC-4626 yield
> system (stable-yield, protocol-asset, agent-token vaults) with a
> Portfolio Router, a Rust signing daemon (`rmpc`), an on-chain policy gateway,
> a web explorer (API + indexer), a human dapp, and agent skill interfaces for
> OpenCode and OpenClaw. Launch chain is Base.
>
> **What this plan does not cover.** Token launch mechanics, tokenomics, agent
> persona, CFO Feed, multi-chain expansion, agent-token shortlist governance,
> RWA/thematic vault implementation, and MCP server implementation are all
> deferred. See `docs/prd.md` open-questions for their TBD status.

## Goal

Deliver a production-ready Robot Money system: auditable smart contracts,
hardened Rust client, reliable full-stack devnet and CI, and documented
agent-skill onboarding. All core application surfaces are implemented; the
goal is to harden, integrate, and ship them reliably.

## Non-goals

- Token launch mechanics, tokenomics, Clanker terms, v1/v2 migration
- Agent-token shortlist governance, inclusion proposals, tier system
- CFO Feed product surface
- Multi-chain expansion beyond Base
- RWA or thematic vault implementation
- MCP server (deferred pending OpenClaw/OpenCode integration review)
- Hosted custody or hosted signing

## Phases

### Phase 1 — Secure Agent Deposit Infrastructure
Goal: Deploy the gateway + vault + Rust client with the minimum secure deposit path.

Status: **Complete.** Contracts (gateway, vault, adapters), Rust client (`rmpc` with
all Phase 1 commands), and the e2e test suite are shipped and exercised in CI
(suites 01–07).

### Phase 2 — Fork E2E System Completeness
Goal: Exercise the deployed-style Robot Money flow against a pinned Base mainnet fork.

Status: **Complete.** Fork e2e tests (`testing/fork-e2e-rust/`) run against a
pinned Base fork with per-test snapshot/revert isolation (suite-05 + 06).

### Phase 3 — Vault Feature Completeness (rmpc read surface)
Goal: `rmpc` can answer vault health, agent position, gateway state, and tx
status without any block-explorer API.

Status: **Complete.** All read commands (`get-vault`, `get-balance`, `get-agent`,
`get-gateway`, `get-deposit`, `get-tx`, `get-allowance`, `get-roles`) plus the
shared `Envelope<T>` output contract and `DecimalU256` newtypes are implemented.
`rmpc status` output is normalized into the same envelope shape.

### Phase 4 — Agent-Harness Installation and Skill Loading
Goal: Install and exercise Robot Money inside OpenCode and OpenClaw runtimes.

Status: **Complete.** Skill package, doctests, opencode smoke and headless CI
(suite-11a/11b), and OpenClaw config (suite-12) are present and wired in CI.

### Phase 4.5 — Full-Stack Hosted Devnet
Goal: Single-command stack: Anvil fork, Postgres, explorer-indexer, explorer-API,
dapp, and deployed gateway in the right startup order with health checks.

Status: **Substantially complete** — smoke-test harness and multi-service
orchestration exist. Integration gaps and reliability issues remain (see
Full-stack integration phase below).

### Phase 5 — Simple Web Explorer API and Database
Goal: Lightweight HTTP API + background indexer over a Postgres database for
browsing Robot Money deposit/vault history.

Status: **Complete.** Explorer API (`clients/explorer-api/`) and indexer
(`services/explorer-indexer/`) are implemented with CI coverage (suite-08).

### Phase 6 — Human Dapp
Goal: Human-facing interface for deposits, withdrawals, agent authorization,
policy, rotation, roles, config export, and history.

Status: **Complete.** Full component set is implemented: deposit/withdraw tab,
authorize/revoke/rotate agent, role management, config export, onboarding
wizard, USDC faucet, history pane, calldata preview, pause flow, and admin
flows. Dapp quality and playwright e2e CI (suites 09–10) are wired.

### Phase 7 — OpenClaw E2E Demo
Goal: Autonomous agent loop against a fork: skill load, chain reads, guarded
deposit, refusal handling, tx reporting.

Status: **Complete.** OpenClaw config and CI demo path (suite-12) are complete.

---

## Remaining Work

### Architectural correctness
Goal: Fix the gateway authority model so each depositor is the sole authority
over her own agent. The current code incorrectly gates agent binding on an admin
role, violating the depositor-sole-authority invariant specified throughout the
product and security docs.

- [ ] Remove admin-gated operator-to-agent binding; depositor sole authority over her own agent

### Contract security hardening
Goal: Fix all Solidity-level security findings from the 2026-05-08 code review.
Three findings touch vault storage and must be serialized; a dev-scout maps the
safe edit order before any implementation begins.

- [ ] dev-scout: map contract security hardening seams and serialization order
- [ ] CEI fix: reorder effects before interactions in gateway `deposit()` and add `ReentrancyGuard`
- [ ] Decimals offset: choose safe ERC-4626 decimals offset to prevent first-depositor inflation
- [ ] MorphoAdapter: verify actual withdrawn amount in `withdraw()`
- [ ] `totalAssets()`: include idle vault USDC balance in accounting
- [ ] `unpause()`: require `ADMIN_ROLE` not `EMERGENCY_ROLE` — mirror gateway asymmetry
- [ ] Fork regression tests for vault accounting attack paths
- [ ] ERC-4626 property-based conformance tests for all vault contracts

### Backend and dapp hardening
Goal: Fix indexer SQL injection surface, explorer-API CORS gap, and two dapp
security gaps. Contract security findings and backend fixes are independent and
can run concurrently after their respective scout gates.

- [ ] dev-scout: map backend hardening seams
- [ ] Indexer: restrict or type-guard `db::count()` to prevent dynamic SQL expansion
- [ ] Explorer API: add CORS configuration for cross-origin dapp access
- [ ] Dapp: verify gateway bytecode hash before admin writes
- [ ] Dapp: fix exported config so it is directly loadable by `rmpc`

### Full-stack integration
Goal: Complete and harden the smoke-test + devnet stack so the full application
can be started and verified in one command, using real contracts.

- [ ] Wire `RobotMoneyVault` + `PassthroughAdapter` into smoke-test devnet (replace `MockVault`)
- [ ] Resolve missing devnet contract addresses, chain ID, and RPC endpoint in bootstrap config
- [ ] Smoke-test: randomize ports and use Bun for dapp build/runtime
- [ ] Smoke-test: fork devnet from Base mainnet with genesis-time USDC balance grant
- [ ] Smoke-test: `--full-stack` flag to boot dapp, explorer-API, and indexer alongside devnet
- [ ] Smoke-test: unified structured logs with rotation for all spawned services
- [ ] Smoke-test: detect compose collision and poll chain health during startup
- [ ] Fork e2e: resolve USDC transparent-proxy admin collision so `rmpc` tests pass without spoofing `from`
- [ ] Dapp: wire Deposit/Withdraw tab to vault ABI with full-stack e2e coverage
- [ ] Dapp: testnet/devnet USDC faucet UX (onboarding seed + admin faucet tab)
- [ ] Dapp: Playwright E2E against full-stack Geth+Lighthouse devnet
- [ ] Dapp: RTL unit tests for refactored admin tabs

### Operator and agent safety
Goal: Surface network environment in the CLI, standardize logging, upload CI
artifacts, and close remaining CI wiring gaps.

- [ ] `rmpc`: surface network environment in CLI logs and agent skill feedback
- [ ] Logging: standardize Rust logging facade across the workspace
- [ ] CI: always upload e2e artifacts as run evidence (screenshots + agent logs)
- [ ] CI: wire opencode-refusal job to existing `testing/doctests` test
- [ ] CI: slim suite-05 by migrating duplicate tests into suite-06

### Release infrastructure
Goal: Ship `rmpc` binary releases, a dapp Docker image, and reliable CI
triggers so operators can install from published artifacts.

- [ ] CI: `rmpc` binary release workflow
- [ ] CI: publish dapp Docker image to GHCR with operator `docker-compose`
- [ ] CI: run all suites unconditionally on push to `dev`
- [ ] CI: `workflow_dispatch` inputs (tag + commit hash) on release workflows
- [ ] Remove deprecated Anvil demo suite (`demo.sh` + suite-15)
- [ ] Audit suite-05 (Anvil mainnet-fork) for necessity vs. suite-06 duplication

### Docs and onboarding
Goal: Publish security review, streamline agent-vendor onboarding, document
devnet configuration, and offer a tunnel-based hosted devnet demo path.

- [ ] Publish 2026-05-09 security review document
- [ ] Create `BOOTSTRAP.md` and simplify `README` to a single agent-onboarding pointer
- [ ] Add agent-vendor bootstrap prompts (OpenCode, OpenClaw, Claude Code)
- [ ] Tunnel hosted devnet demo + wallet-routed dapp reads
