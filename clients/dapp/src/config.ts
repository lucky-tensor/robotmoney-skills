/**
 * Canonical: docs/implementation-plan.md §12 — Phase 6 Human Dapp Controls
 *
 * Runtime feature flags for the dapp.
 *
 * DAPP_BROWSER_KEYGEN_ENABLED controls whether the browser-generated
 * credential path is available. See docs/technical/dapp-browser-keygen-review.md
 * for the security review and go/no-go decision (GO, 2026-05-07).
 *
 * SAFETY: This flag MUST remain false in production build configs. The ADR
 * (§6.2) requires all enabling conditions to hold before the flag is lifted:
 *   1. rmpc unsafe_for_production guard is implemented and tested ✓ (this PR)
 *   2. Code-review checklist §7 is verified ✓ (this PR)
 *   3. CI grep check §8 passes ✓ (see .github/workflows/ci.yml keygen sentinel)
 *   4. Environment is fork or devnet (runtime chain-id check enforced below)
 *   5. UI warning dialog and unsafe_for_production label are present ✓ (keygen.ts)
 */

/** Production chain IDs. Mirrors PRODUCTION_CHAIN_IDS in clients/rust-payment-client/src/config.rs. */
export const PRODUCTION_CHAIN_IDS: readonly bigint[] = [
  1n,     // Ethereum mainnet
  10n,    // Optimism
  8453n,  // Base mainnet
  42161n, // Arbitrum One
];

/**
 * Whether the browser-keygen credential path is enabled.
 *
 * Read from VITE_DAPP_BROWSER_KEYGEN_ENABLED at build time. Defaults to
 * `false` — the external-signer path remains the only supported path unless
 * explicitly enabled for a fork/devnet build.
 */
export const DAPP_BROWSER_KEYGEN_ENABLED: boolean =
  import.meta.env.VITE_DAPP_BROWSER_KEYGEN_ENABLED === "true";

/**
 * Runtime check: returns `true` only if the given chain id is NOT a production
 * chain. Used by the keygen component to enforce the chain-id boundary at
 * runtime, independent of the build-time flag.
 *
 * This is the dapp-side complement to the rmpc `unsafe_for_production` guard.
 */
export function isDevnetChain(chainId: bigint): boolean {
  return !PRODUCTION_CHAIN_IDS.includes(chainId);
}

/**
 * Returns `true` if the browser-keygen path is available for the current
 * chain. Both the build-time flag and the runtime chain-id check must pass.
 */
export function isBrowserKeygenAvailable(chainId: bigint): boolean {
  return DAPP_BROWSER_KEYGEN_ENABLED && isDevnetChain(chainId);
}
