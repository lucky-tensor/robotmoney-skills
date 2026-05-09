# Full-Stack Smoke Test Design

> Canonical: `docs/implementation-plan.md` §10.5 (Phase 4.5 — Full-stack hosted devnet).
> Implementation: issue #146.

This document records the design decisions for the full-stack integration
test harness that validates the complete Robot Money service graph: Geth
devnet, deployed contracts, explorer indexer and API, and dapp running
together as a single orchestrated stack.

---

## Guiding principle: the test runner owns the stack

The devnet lifecycle — boot, contract deployment, health-wait, teardown —
is controlled entirely by Rust test code. The CI workflow calls `cargo test`;
it has no knowledge of Docker or service orchestration. This is the same
principle used by the existing Geth e2e harness in
`testing/ethereum-testnet/e2e-rust/`, extended to the full service graph.

**Why this matters.** If the workflow controls the devnet, ordering is
enforced by YAML job/step sequencing, which is fragile and opaque. When
the test code controls the devnet, ordering is enforced by ordinary Rust
async logic — explicit, reviewable, and testable in isolation. Failures
surface as test failures with stack traces, not as mysterious CI timing
problems.

---

## Devnet: real Geth+Lighthouse, not Anvil

The full-stack fixture uses the existing Geth+Lighthouse compose stack
(`testing/ethereum-testnet/config/docker-compose.yaml`), not Anvil.

Anvil is a simulated EVM suitable for fast unit-level fixture work. The
full-stack smoke tests exercise the complete service graph — real mempool
behaviour, real consensus, real block production — so they require a real
execution client. The Geth devnet is already proven in CI and starts from
a fully deterministic genesis, making it the right substrate.

The genesis configuration is fixed, so block 0 is always the same seed
state. Every devnet instance is therefore a reproducible digital twin: the
same accounts, the same balances, the same chain parameters, every run.

---

## Port allocation

Every port used by the stack is chosen by binding to `0` (OS-assigned)
at fixture spawn time and recorded in `FullStackFixture`. No port number
is hardcoded anywhere in the harness — not in the compose file, not in
the test code, not in the CI workflow.

```rust
struct FullStackFixture {
    geth_rpc_port: u16,
    geth_authrpc_port: u16,
    beacon_port: u16,
    postgres_port: u16,
    explorer_api_port: u16,
    dapp_port: u16,
    // derived URLs for convenience
    rpc_url: String,
    explorer_api_url: String,
    dapp_url: String,
    ...
}
```

`spawn()` picks each port by opening a `TcpListener` on `127.0.0.1:0`,
reading the OS-assigned port, closing the listener, then passing that
port to the compose service via `--env` or `--env-file`. The compose
file exposes each service port via the env var (e.g.
`GETH_RPC_PORT`, `EXPLORER_API_PORT`) rather than a fixed `ports:`
mapping.

This makes parallel runs safe by construction: two fixture instances
running simultaneously will never collide on a port. Parallel execution
is not the recommended default (see BeforeAll vs BeforeEach below), but
the harness must not make it impossible or silently broken.

---

## Fixture lifecycle

The `FullStackFixture` struct in the test binary manages the full
lifecycle. Its `spawn()` method runs in `BeforeAll` (via `OnceLock`);
its `Drop` impl runs teardown unconditionally when the binary exits.

```
spawn():
  1. allocate randomized ports for all services
  2. docker compose up -d geth beacon validator-{1..4}
     (ports injected via env vars)
  3. poll geth RPC on allocated port until healthy (eth_blockNumber succeeds)
  4. forge script Deploy.s.sol  →  parse addresses from output
  5. docker compose up -d postgres explorer-indexer explorer-api dapp
     (addresses + ports injected as env vars)
  6. poll explorer-api /health on allocated port until 200
  7. return FullStackFixture { rpc_url, gateway_addr, explorer_api_url, dapp_url, ... }

Drop:
  docker compose down -v --remove-orphans
```

Contract deployment (step 4) is a `std::process::Command` call to
`forge script`, the same mechanism the harness already uses for `cast`
and `docker compose`. The addresses are parsed from the JSON deployment
output and passed to the remaining services as environment variables —
no deployer container, no chicken-and-egg problem in the compose file.

---

## BeforeAll vs BeforeEach

The Geth+Lighthouse stack takes 60-120 seconds to reach a fully indexed
state. A fresh devnet per test (`BeforeEach`) is therefore only viable for
a very small number of high-value isolation tests.

The default is **BeforeAll**: one devnet per test binary, shared across
all tests in that binary. Tests must not leave persistent mutations that
affect other tests. The standard mitigation is per-test isolation at the
application layer: each test generates a fresh ephemeral agent EOA and
keystore, so contract state (agent authorization, deposits) is scoped to
that test's addresses and does not bleed across.

---

## CI entrypoint

```yaml
- name: Full-stack smoke tests
  working-directory: testing/ethereum-testnet/e2e-rust
  run: cargo test --release --test full_stack -- --test-threads=1 --nocapture

- name: Tear down (always)
  if: always()
  working-directory: testing/ethereum-testnet/config
  run: docker compose down -v --remove-orphans || true
```

The workflow step is thin by design. All meaningful logic lives in the
Rust fixture. The explicit teardown step at the workflow level is a safety
net for the case where the Rust process exits uncleanly and `Drop` does
not run.

---

## Relationship to existing harnesses

| Harness | Devnet | Lifecycle owner | Scope |
|---|---|---|---|
| `smoke.rs`, `scenarios.rs`, `window_cap.rs` | Geth+Lighthouse | Rust `Fixture` | rmpc client behaviour |
| `full_stack.rs` (issue #146) | Geth+Lighthouse + full service graph | Rust `FullStackFixture` | end-to-end service integration |
| `opencode-headless-deposit.yml` | Anvil fork | CI workflow steps | OpenCode agent behaviour |
| `dapp.yml` e2e | Anvil (local, no fork) | CI workflow steps | dapp UI |

The full-stack harness sits between the rmpc unit harnesses and the
OpenCode headless tests in the integration pyramid. It validates that
services connect to each other correctly; it does not re-test rmpc
command behaviour or OpenCode agent reasoning.
