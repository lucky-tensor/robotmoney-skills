# ADR — Dapp Browser-Generated Credentials: Security Review and DAPP_BROWSER_KEYGEN_ENABLED Gate

> Scope: Phase 6 (Human Dapp Controls) security review required by `docs/implementation-plan.md` §12
> before `DAPP_BROWSER_KEYGEN_ENABLED` can be set to `true`. Addresses key-custody boundary, entropy
> source, export format, risk class, and go/no-go decision for browser-side agent credential
> generation. Companion to `docs/technical/dapp-credential-decisions.md` (credential model choices)
> and `docs/security-model.md` §11 (off-chain dapp/frontend threat table).
>
> This ADR does not ship dapp code. It records the go/no-go decision and the conditions that must
> hold before the feature can be enabled. Implementation issues for the dapp UI components are
> separate.

---

## 1. Status

**Decision: GO — fork/devnet mode only, with mandatory risk labeling.**

Authored 2026-05-07 against `docs/implementation-plan.md` §12 on branch
`feat/115-feat-dapp-browser-keygen-security-review-and-dap`. No prior ADR exists for this
credential path.

`DAPP_BROWSER_KEYGEN_ENABLED` may be set to `true` when the runtime environment is fork or devnet
(chain id not in the production set: Base mainnet `8453`, Ethereum mainnet `1`, Optimism `10`,
Arbitrum One `42161`). The flag must remain `false` for any production chain.

---

## 2. Context

`docs/implementation-plan.md` §12 states:

> "If browser-generated credentials are considered, that requires a separate design review.
> Preferred path is: user creates/holds the credential in the target signer backend, dapp
> registers the public address and policy. Any secret export must be explicit, encrypted where
> possible, and labeled as unsafe for production if it is software-backed."

The Phase 6 dapp needs to create or register agent credentials so a human can authorize a
fork/devnet agent without touching raw calldata. Two paths exist:

1. **External signer path (preferred for production):** the user generates a key in their own
   signer backend (hardware wallet, `cast wallet`, encrypted keystore), then pastes the public
   address into the dapp for registration. The dapp never sees the private key.

2. **Browser-keygen path (subject of this ADR):** the dapp calls `crypto.getRandomValues` in the
   browser to generate an ephemeral ECDSA keypair, displays the private key exactly once for the
   user to copy, uses the public address for on-chain registration, and discards the private key
   from memory when the user navigates away. This path is faster for fork/devnet experimentation
   but carries higher risk.

Without a go decision on path 2, the Phase 6 acceptance criterion — "A human can authorize a
fork/devnet agent without touching raw contract calldata" — can still be met via path 1. However,
path 1 requires the user to have an external signer toolchain installed, which increases friction
for first-time evaluators running against a devnet fork. A gated, clearly-labeled browser-keygen
path reduces that friction without extending the risk surface to production.

Four questions gate the go/no-go:

1. Is the entropy source sufficient for a fork/devnet-only key?
2. Can the dapp guarantee it never persists the private key outside the session?
3. Is the export format safe to pass to `rmpc`?
4. Is the residual risk class acceptable at fork/devnet scope?

---

## 3. Entropy Source

**Decision: `crypto.getRandomValues` via the Web Crypto API — sufficient for fork/devnet.**

`window.crypto.getRandomValues` is the browser's CSPRNG, mandated by the W3C Web Cryptography
API specification (Level 2, §14.1) and implemented by all browsers in scope (Chrome ≥ 37,
Firefox ≥ 21, Safari ≥ 11, all Chromium-based). It draws from the OS entropy pool (Linux
`getrandom(2)`, macOS `CCRandomGenerateBytes`, Windows `BCryptGenRandom`), the same source
used by hardware-adjacent CSPRNG paths in native code.

**Residual risk:** the entropy quality is only as good as the OS at page-load time. A freshly
booted VM with minimal entropy accumulation could produce a weaker seed. In practice, a browser
session long enough to reach the dapp has accumulated sufficient entropy for a 256-bit key.

**Decision boundary:** the entropy source is acceptable for fork/devnet keys whose worst-case loss
is the fork's ephemeral USDC allocation. It is not an acceptable substitute for a hardware wallet
or KMS-backed key on production chains, where a compromised private key has irreversible mainnet
consequences.

**Rejected alternatives:**
- *WebAuthn / FIDO2 credential storage:* this would generate a non-extractable key in the
  platform authenticator, which is actually stronger, but also means the user can never export
  the private key for use in `rmpc`. Incompatible with the export requirement.
- *User-provided entropy via typing:* adds UX complexity and invites weak passphrases. The OS
  CSPRNG is strictly better.

---

## 4. Key-Custody Boundary

**Decision: the dapp takes zero-retention custody — private key lives only in JavaScript heap
during the generation session; never written to storage or sent over the network.**

The custody boundary is enforced by the following rules, all of which must be verified by code
review before `DAPP_BROWSER_KEYGEN_ENABLED` is set to `true`:

1. **No `localStorage` or `sessionStorage` writes of the private key.** The key may appear in
   component state as a hex string for display purposes only (the one-time disclosure step), and
   must be cleared from component state when the user explicitly acknowledges copying it.
2. **No `indexedDB` writes of the private key.**
3. **No network requests containing the private key.** All outbound calls from the dapp are
   on-chain RPC (`eth_sendRawTransaction`, `eth_call`, etc.) or read-only REST. None carry
   key material.
4. **No log statements emitting the private key.** `console.log`, `console.debug`, and any
   analytics/error-tracking hooks must not receive the key string.
5. **The public address is the only derived value retained** after the user confirms the key has
   been copied. The address is used for on-chain registration and is not a secret.

**Verification method:** a code-review checklist (§7 below) confirms each rule before the
feature is enabled. Automated grep-based CI checks (§8) detect accidental storage writes in the
keygen code path.

**Accepted residual custody risk:** the browser memory contents are accessible to other scripts
on the same origin (XSS), browser extensions with the `storage` or `tabs` permission, and the
browser process's memory dump. This is acceptable at fork/devnet scope — the key controls only
ephemeral devnet funds. It is not acceptable for production keys.

---

## 5. Export Format

**Decision: plain-hex private key with `unsafe_for_production: true` label in the exported
TOML config.**

The export path produces a `rmpc`-compatible TOML config fragment:

```toml
# GENERATED BY DAPP BROWSER KEYGEN — FORK/DEVNET ONLY
# unsafe_for_production = true
# This key was generated in a browser session. It is not hardware-backed.
# Use only against fork and devnet environments.

[signer]
type = "local_key"
private_key = "0x<hex>"
unsafe_for_production = true

[network]
chain_id = <devnet_chain_id>
rpc_url = "<devnet_rpc>"
```

**Label requirements:**

- The UI must display a warning dialog before the private key is shown, explaining:
  - The key is software-generated in the browser.
  - It is suitable for fork/devnet only.
  - The user is responsible for copying and securing the key.
  - The dapp will not store or recover the key.
- The exported TOML file must contain `unsafe_for_production = true` at the `[signer]` section.
- The filename must include the suffix `-DEVNET-UNSAFE` (e.g., `rmpc-agent-config-DEVNET-UNSAFE.toml`).

**`rmpc` behavior when `unsafe_for_production = true`:**

`rmpc` must refuse to use this config against a production chain. When loading a config with
`unsafe_for_production = true`, `rmpc self-check` must:
1. Verify the connected chain id is not in the production set.
2. Emit a log-level `WARN` entry: `[keygen] unsafe_for_production key detected; refusing
   production chain <chain_id>`.
3. Exit with a non-zero status if the chain id is production.

This guard is the backstop against a devnet key accidentally being used on mainnet. Implementation
of the guard in `rmpc` is a hard prerequisite before `DAPP_BROWSER_KEYGEN_ENABLED` is set to
`true` in any build.

**Rejected alternatives:**
- *Encrypted keystore (EIP-55 or JSON keystore):* stronger export, but requires the user to
  choose a password that `rmpc` must also prompt for. Adds friction in a fork/devnet context
  where speed of experimentation matters. Can be a follow-up improvement.
- *QR code only (no file export):* reduces clipboard-swap risk but requires `rmpc` to accept
  QR input, which is not in scope for Phase 6 or Phase 7.

---

## 6. Risk Class and Decision

### 6.1 Risk class

| Dimension | Assessment |
|---|---|
| Entropy | CSPRNG-grade; acceptable for non-production |
| Key custody | Zero-retention browser session; no persistence |
| Key scope | Fork/devnet only; chain-id guard in `rmpc` enforces boundary |
| Loss scenario | Ephemeral devnet USDC; no mainnet funds at risk under correct use |
| Misuse scenario | User re-uses key on mainnet, ignoring `unsafe_for_production` label |
| Misuse likelihood | Low — `rmpc` blocks production use; label is explicit |
| Misuse blast radius | Full loss of whatever the user funded on mainnet (operator error, not protocol failure) |
| XSS extraction | High severity IF XSS exists during keygen session; mitigated by dapp CSP (see §11 of `docs/security-model.md`) |
| Extension extraction | Accepted residual; scoped to fork/devnet by flag |

**Risk class: Medium for the misuse scenario; Low for normal fork/devnet operation.** Acceptable
at current scope.

### 6.2 Go/No-Go decision

**GO.**

Conditions for enabling `DAPP_BROWSER_KEYGEN_ENABLED`:

1. The `rmpc` `unsafe_for_production` guard is implemented and tested (§5).
2. The code-review checklist in §7 is verified by a second reviewer.
3. The CI grep check in §8 passes.
4. The environment is fork or devnet (chain id not in production set).
5. The UI warning dialog and `unsafe_for_production` label are present in the export flow.

If any condition is unmet, `DAPP_BROWSER_KEYGEN_ENABLED` remains `false` and the external signer
path (§2, path 1) is the only supported credential registration method.

---

## 7. Code-Review Checklist (required before enabling flag)

The following checklist must be completed by a second reviewer before any PR sets
`DAPP_BROWSER_KEYGEN_ENABLED = true`:

- [ ] `crypto.getRandomValues` is the only entropy source in the keygen path.
- [ ] No `localStorage.setItem` / `sessionStorage.setItem` call receives the private key string
  or any variable that holds it.
- [ ] No `indexedDB.transaction` or `indexedDB.put` call receives the private key.
- [ ] No `fetch` / `XMLHttpRequest` / WebSocket send includes the private key in body, headers,
  or URL parameters.
- [ ] No `console.log` / `console.debug` / `console.error` / Sentry / analytics hook receives
  the private key.
- [ ] Component state holding the private key is set to `null` / empty string after the user
  confirms the key has been copied.
- [ ] The UI shows the warning dialog (§5) before displaying the private key.
- [ ] The exported TOML contains `unsafe_for_production = true` under `[signer]`.
- [ ] The exported filename includes `-DEVNET-UNSAFE`.
- [ ] `rmpc self-check` exits non-zero on a production chain id when `unsafe_for_production = true`.
- [ ] `DAPP_BROWSER_KEYGEN_ENABLED` is `false` in all production build configs and environment
  variable defaults.

---

## 8. Automated Verification (CI)

The following automated checks must pass on every PR that touches the keygen code path:

1. **Grep sentinel:** the CI job must verify that the keygen component does not call
   `localStorage`, `sessionStorage`, or `indexedDB` with any variable named `*key*`, `*priv*`,
   or `*secret*`. A failing grep must fail the PR.
2. **`unsafe_for_production` label test:** a test renders the keygen export flow and asserts
   `unsafe_for_production: true` appears in the TOML output string.
3. **`rmpc self-check` production guard test:** a fork test enables the flag, generates a config
   with `unsafe_for_production = true`, runs `rmpc self-check` against a fork of Base mainnet
   (chain id 8453), and asserts exit code is non-zero.
4. **Regression:** existing dapp workflows (AdminFlow, PauseFlow, TxPreview) are exercised with
   `DAPP_BROWSER_KEYGEN_ENABLED` both `true` and `false` to confirm flag state does not affect
   other flows.

---

## 9. Impact on `docs/implementation-plan.md` §12

The acceptance criterion "A human can authorize a fork/devnet agent without touching raw contract
calldata" is satisfiable via either the external signer path (path 1) or the browser-keygen path
(path 2, subject to conditions in §6.2). This ADR enables path 2 as an optional, clearly-labeled
alternative that reduces setup friction for fork/devnet evaluators.

No §12 acceptance criterion changes. This ADR provides the missing security review that §12
explicitly requires before browser keygen can ship.

---

## 10. Open Follow-Ups

- **Encrypted keystore export** (future improvement): offer EIP-55 JSON keystore as an
  alternative export format so the key survives across sessions when the user chooses to accept
  the password-protection tradeoff. Track as a separate issue.
- **CSP policy for the dapp** (prerequisite for public launch, see `docs/security-model.md`
  §11): the XSS extraction risk in §6.1 is only acceptable at fork/devnet scope. Before the dapp
  ships to users on a public domain, the CSP/SRI/hosting hardening work in §11 of the security
  model must complete.
- **WebAuthn non-extractable credential** (future improvement): for users who want a
  hardware-backed key that stays in the platform authenticator, a separate credential path using
  WebAuthn's `authenticatorMakeCredential` with `extractable: false` could replace the
  browser-keygen path for scenarios where the private key never needs to leave the browser. Track
  separately; out of scope for Phase 6/7.

---

## 11. References

- `docs/implementation-plan.md` §12 — Phase 6 Human Dapp (credential model constraint this ADR
  resolves).
- `docs/security-model.md` §11 — Off-chain dapp/frontend threat table (XSS, build-pipeline,
  hosting model rows relevant to §6.1 above).
- `docs/security-model.md` §10 — Off-chain agent access layer (software-key extraction row:
  "HSM/KMS/Secure Enclave/TPM preferred; software is explicit opt-in").
- W3C Web Cryptography API Level 2 §14.1 — `getRandomValues` specification.
- Issue #115 — this ADR.
