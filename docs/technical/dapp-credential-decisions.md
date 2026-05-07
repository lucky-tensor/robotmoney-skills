# ADR — Dapp Credential Model: Choices and Constraints for Phase 6

> Scope: Phase 6 (Human Dapp Controls) credential model decisions for `docs/implementation-plan.md`
> §12. Records the choices governing how agent credentials are created, registered, and exported
> through the Robot Money dapp. The browser-keygen security review lives in
> `docs/technical/dapp-browser-keygen-review.md` and is a prerequisite for the browser-keygen
> path described here.

---

## 1. Status

**Accepted.** Authored 2026-05-07 against `docs/implementation-plan.md` §12. Companion to
`docs/technical/dapp-browser-keygen-review.md` (browser keygen go/no-go) and
`docs/security-model.md` §10–§11 (agent and frontend threat tables).

---

## 2. Context

Phase 6 requires a human to authorize a fork/devnet agent without touching raw calldata. The
agent authorization flow has two separable steps:

1. **Credential creation:** produce a public/private keypair for the agent signer.
2. **Credential registration:** grant `AGENT_ROLE` on-chain for the agent's public address, set
   policy parameters (share receiver, caps, valid-until), and export an `rmpc` config.

Step 1 has two supported paths. Step 2 is identical regardless of path.

---

## 3. Credential Creation Paths

### 3.1 External signer path (preferred for all environments)

The user generates the keypair outside the dapp — using a hardware wallet, `cast wallet new`,
or any encrypted keystore tool — and pastes only the public address into the dapp. The dapp
never sees the private key. This is the preferred path for all environments including
fork/devnet.

**Advantages:** zero custody risk in the dapp; works with hardware wallets for operators who
want production-grade key hygiene even on devnet.

**Disadvantages:** requires the user to have a signer toolchain installed and know how to use it.
Higher friction for first-time evaluators.

### 3.2 Browser-keygen path (fork/devnet only, requires `DAPP_BROWSER_KEYGEN_ENABLED = true`)

The dapp calls `crypto.getRandomValues` to generate an ephemeral ECDSA keypair, displays the
private key once for the user to copy, and uses the public address for on-chain registration.
The private key is never persisted. Exports are labeled `unsafe_for_production`.

**Requires:** the security review in `docs/technical/dapp-browser-keygen-review.md` to have a
recorded GO decision (it does, as of 2026-05-07) and all enabling conditions in §6.2 of that
document to be satisfied before the flag is set to `true`.

**Flag default:** `DAPP_BROWSER_KEYGEN_ENABLED = false`. Must remain `false` in production build
configs.

---

## 4. Credential Registration

Regardless of which creation path is used, registration is identical:

1. Dapp reads the agent's public address (typed or pasted by user).
2. Dapp reads current chain state: agent authorization status, current caps, gateway config.
3. User configures policy: share receiver, valid-until, max-per-deposit, max-per-window.
4. Dapp builds the `grantAgentRole` + policy-configuration calldata and presents a transaction
   preview: decoded target, function selector, parameter values, and expected risk.
5. User's connected wallet signs and submits.
6. Dapp confirms on-chain state change before declaring success.
7. Dapp optionally exports an `rmpc` config TOML for the agent runtime.

---

## 5. Export Format

The exported `rmpc` config TOML format is defined in `docs/technical/dapp-browser-keygen-review.md`
§5. Key constraints:

- If the credential was browser-generated, `unsafe_for_production = true` is mandatory in
  `[signer]`.
- If the credential was externally generated, `unsafe_for_production` is omitted or `false`.
- The network section records the chain id and RPC URL used during registration.
- `rmpc self-check` enforces the `unsafe_for_production` guard (refuses production chain ids
  when the flag is set).

---

## 6. Credential Revocation

The dapp must also support revocation:

1. User selects an authorized agent address.
2. Dapp shows current policy and authorization status.
3. User initiates revocation.
4. Dapp builds `revokeAgentRole` calldata with the same transaction preview format as
   registration.
5. User signs and submits.
6. Dapp confirms `rmpc self-check` returns non-zero for the revoked credential (confirms the
   agent can no longer deposit).

---

## 7. Non-Decisions (out of scope)

- **HSM/KMS-backed browser keygen** — using the WebCrypto API's `extractable: false` with
  WebAuthn for non-exportable hardware-backed keys. This is a future improvement path; the
  current ADR scopes to extractable software keys only.
- **Credential rotation UX** — multi-step rotation workflows (authorize new, revoke old,
  update config). Rotation is supported at the contract level; the dapp UX for atomic rotation
  is out of Phase 6 scope.
- **Production mainnet keygen through the dapp** — explicitly out of scope. The browser-keygen
  path is fork/devnet only.

---

## 8. References

- `docs/implementation-plan.md` §12 — Phase 6 Human Dapp (credential model section this doc
  expands).
- `docs/technical/dapp-browser-keygen-review.md` — Browser keygen security review and go/no-go
  decision (prerequisite for §3.2).
- `docs/security-model.md` §10 — Agent access layer threat table.
- `docs/security-model.md` §11 — Dapp/frontend threat table.
- Issue #115 — browser keygen security review issue that triggered this ADR pair.
