/**
 * React hook — fetch gateway bytecode and derive a VerificationState.
 *
 * Calls the injected EIP-1193 provider (`window.ethereum`) directly for
 * `eth_getCode` instead of going through wagmi's `unstable_connector`
 * transport. That transport is documented as best-effort and surfaces
 * wallet-side errors as cryptic "Requested resource not available /
 * RPC endpoint returned too many errors" messages; calling the wallet
 * provider directly yields the real wallet error string, which is what
 * the operator needs to see when verification is refused.
 *
 * Reads still traverse the user's wallet RPC per
 * `docs/security/dapp-topology.md` §2 — the wallet is the network
 * endpoint, the dapp just asks it for code.
 *
 * The hook runs once per mount + when the wallet's chain id changes.
 * It does not poll; the operator reloads the page to re-verify.
 */
import { useAccount, useChainId } from "wagmi";
import { useEffect, useState } from "react";
import type { Hex } from "viem";
import { computeVerificationState, ZERO_ADDRESS } from "./gatewayVerifier";
import type { VerificationState } from "./gatewayVerifier";
import { targetChainId } from "./wagmi";

export { type VerificationState };

interface Eip1193Provider {
  request: (args: { method: string; params?: unknown[] }) => Promise<unknown>;
}

function getInjectedProvider(): Eip1193Provider | undefined {
  if (typeof window === "undefined") return undefined;
  return (window as unknown as { ethereum?: Eip1193Provider }).ethereum;
}

/**
 * Returns the current VerificationState for the gateway contract.
 *
 * @param gatewayAddress   On-chain address of the gateway contract.
 * @param expectedCodeHash Operator-pinned runtime bytecode hash
 *                         (`VITE_GATEWAY_EXPECTED_CODE_HASH`). Pass
 *                         empty string / undefined when the env var is
 *                         absent — the hook will immediately return a
 *                         refused state without making an RPC call.
 */
export function useGatewayVerifier(
  gatewayAddress: string,
  expectedCodeHash: string | undefined,
): VerificationState {
  const [state, setState] = useState<VerificationState>(() =>
    computeVerificationState(gatewayAddress, expectedCodeHash, undefined),
  );
  const { isConnected } = useAccount();
  const chainId = useChainId();

  useEffect(() => {
    const initial = computeVerificationState(gatewayAddress, expectedCodeHash, undefined);
    if (initial.status === "refused") {
      setState(initial);
      return;
    }
    if (!gatewayAddress || gatewayAddress === ZERO_ADDRESS || !expectedCodeHash) {
      return;
    }
    if (!isConnected) {
      setState({
        status: "refused",
        reason: "Wallet not connected. Click Connect Wallet to verify gateway bytecode.",
      });
      return;
    }
    if (targetChainId !== undefined && chainId !== targetChainId) {
      setState({
        status: "refused",
        reason: `Wallet is on chain ${chainId}, expected ${targetChainId}. Use the Switch Chain button.`,
      });
      return;
    }

    const provider = getInjectedProvider();
    if (!provider) {
      setState({
        status: "refused",
        reason: "No injected wallet provider (window.ethereum is undefined).",
      });
      return;
    }

    let cancelled = false;

    async function verify(p: Eip1193Provider) {
      try {
        const code = (await p.request({
          method: "eth_getCode",
          params: [gatewayAddress, "latest"],
        })) as Hex | null | undefined;
        if (cancelled) return;
        // eth_getCode returns "0x" for an EOA / un-deployed contract.
        const resolvedCode: Hex | null =
          code === undefined || code === null || code === "0x" ? null : code;
        setState(computeVerificationState(gatewayAddress, expectedCodeHash, resolvedCode));
      } catch (err) {
        if (cancelled) return;
        const message = (err as { message?: string }).message ?? String(err);
        setState({
          status: "refused",
          reason: `Wallet returned an error for eth_getCode(${gatewayAddress}): ${message}`,
        });
      }
    }

    void verify(provider);

    return () => {
      cancelled = true;
    };
  }, [gatewayAddress, expectedCodeHash, isConnected, chainId]);

  return state;
}
