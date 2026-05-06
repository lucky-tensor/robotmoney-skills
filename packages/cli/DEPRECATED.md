# DEPRECATED — `@robotmoney/cli` (TypeScript)

This package is **deprecated and kept only for reference**. As of
2026-05-06, the replacement path for relevant TypeScript CLI features
is the Rust client plus on-chain policy gateway:

- a Rust signing client (`rmpc`), and
- an on-chain policy gateway that wraps `vault.deposit()` with
  per-agent caps.

The current MVP is only the guarded autonomous-agent deposit path. Full
replacement of the old CLI surface is intended, but the architecture is
TBD for read-command parity, withdraw/redeem flows, basket routing,
simulation/state overrides, OWS or wallet-adapter UX, and mainnet
configuration management.

See:

- `docs/architecture-proposal-v0.md` — security architecture.
- `docs/implementation-plan-mvp.md` — buildable slice.

Files in `packages/cli/src/` are preserved as historical reference for
patterns (RPC fallback, error decoding, gas estimation, basket
encoding, simulation with state overrides) that may inform the Rust
implementation but should not be treated as the supported product
surface.

Do not extend this package. New work goes into the Rust client.
