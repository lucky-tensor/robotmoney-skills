/**
 * AgentsPanel — gates the full per-user agent management surface.
 *
 *   no wallet            → connect prompt
 *   wallet, no agent     → OnboardingWizard (bootstrap → address → authorize)
 *   wallet, has agent    → full AdminFlow (all management tabs)
 *
 * "Has agent" today reads a localStorage flag set optimistically when the
 * user signs Authorize — see useAgentRegistration.ts for the placeholder
 * rationale and the on-chain follow-up.
 */
import { useAccount, useConnect } from "wagmi";
import type { Address } from "viem";
import { AdminFlow } from "./AdminFlow";
import { OnboardingWizard } from "./OnboardingWizard";
import { useAgentRegistration } from "../lib/useVaultRegistration";
import type { VerificationState } from "../lib/useGatewayVerifier";
import type { PreviewContext } from "../lib/preview";

type Props = Readonly<{
  gatewayAddress: Address;
  vaultAddress: Address;
  gatewayVerificationState: VerificationState;
  envClass: "fork" | "devnet" | "testnet" | "mainnet";
  flagEnv: Record<string, string | undefined>;
  now: number;
}>;

export function AgentsPanel(props: Props) {
  const { isConnected } = useAccount();
  const { connect, connectors } = useConnect();
  const status = useAgentRegistration(props.envClass);

  if (!isConnected) {
    return (
      <main className="agents-gate" data-testid="agents-gate-connect">
        <section>
          <h2>Connect wallet</h2>
          <p>Connect a wallet to authorize your first agent and manage your policies.</p>
          {connectors[0] ? (
            <button
              type="button"
              data-testid="connect-wallet"
              onClick={() => connect({ connector: connectors[0] })}
            >
              Connect wallet
            </button>
          ) : (
            <p data-testid="no-connectors" className="hint">
              No browser wallet detected. Install a wallet extension to continue.
            </p>
          )}
        </section>
      </main>
    );
  }

  if (status === "unregistered") {
    const ctx: PreviewContext = {
      gateway: props.gatewayAddress,
      gatewayCodeHashVerified: props.gatewayVerificationState.status === "verified",
      envClass: props.envClass,
    };
    return <OnboardingWizard gatewayAddress={props.gatewayAddress} ctx={ctx} now={props.now} />;
  }

  return (
    <AdminFlow
      gatewayAddress={props.gatewayAddress}
      vaultAddress={props.vaultAddress}
      gatewayVerificationState={props.gatewayVerificationState}
      envClass={props.envClass}
      flagEnv={props.flagEnv}
      now={props.now}
    />
  );
}
