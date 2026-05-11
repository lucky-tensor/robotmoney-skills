/**
 * AgentsPanel — gates the full per-user agent management surface.
 *
 *   no wallet            → connect prompt
 *   wallet, no agent     → AdminFlow in registration mode (Authorize only)
 *   wallet, has agent    → full AdminFlow (all management tabs)
 *
 * "Has agent" today reads a localStorage flag set optimistically when
 * the user clicks Authorize — see useAgentRegistration.ts for the
 * placeholder rationale and the on-chain follow-up.
 */
import { useAccount } from "wagmi";
import type { Address } from "viem";
import { AdminFlow } from "./AdminFlow";
import { useAgentRegistration } from "../lib/useVaultRegistration";
import type { VerificationState } from "../lib/useGatewayVerifier";

interface AgentsPanelProps {
  gatewayAddress: Address;
  vaultAddress: Address;
  gatewayCodeHashVerified: boolean;
  gatewayVerificationState: VerificationState;
  envClass: "fork" | "devnet" | "testnet" | "mainnet";
  flagEnv: Record<string, string | undefined>;
}

export function AgentsPanel(props: AgentsPanelProps) {
  const { isConnected } = useAccount();
  const status = useAgentRegistration(props.envClass);

  if (!isConnected) {
    return (
      <main className="agents-gate" data-testid="agents-gate-connect">
        <section>
          <h2>Wallet required</h2>
          <p>Connect a wallet (above) to authorize your first agent and manage your policies.</p>
        </section>
      </main>
    );
  }

  return (
    <AdminFlow
      gatewayAddress={props.gatewayAddress}
      vaultAddress={props.vaultAddress}
      gatewayCodeHashVerified={props.gatewayCodeHashVerified}
      gatewayVerificationState={props.gatewayVerificationState}
      envClass={props.envClass}
      flagEnv={props.flagEnv}
      registrationMode={status === "unregistered"}
    />
  );
}
