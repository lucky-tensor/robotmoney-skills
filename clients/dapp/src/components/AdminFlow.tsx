/**
 * AdminFlow — orchestrates the agent-management tabs. Each tab owns
 * its wallet hooks and preview pipeline; this component routes shared
 * state (agent address, share receiver) between tabs that reference
 * them and delegates tab assembly to `buildAdminTabs`.
 */
import { useState } from "react";
import { useAccount, useChainId, useReadContract } from "wagmi";
import type { Address } from "viem";
import { gatewayAbi } from "../lib/abi";
import type { PreviewContext } from "../lib/preview";
import { Tabs } from "./Tabs";
import { resolveFlags } from "../lib/featureFlags";
import type { VerificationState } from "../lib/useGatewayVerifier";
import { buildAdminTabs } from "./admin/buildAdminTabs";

type Props = Readonly<{
  gatewayAddress: Address;
  vaultAddress: Address;
  gatewayVerificationState: VerificationState;
  envClass: PreviewContext["envClass"];
  flagEnv: Record<string, string | undefined>;
  /**
   * When true the user hasn't authorized any agent yet — render only
   * the Authorize tab so the registration step is the focused next
   * action. AgentsPanel sets this from useAgentRegistration.
   */
  registrationMode?: boolean;
}>;

export function AdminFlow(props: Props) {
  const flags = resolveFlags(props.flagEnv);
  const { isConnected } = useAccount();
  const chainId = useChainId();

  const { data: usdcAddressData } = useReadContract({
    address: props.gatewayAddress,
    abi: gatewayAbi,
    functionName: "usdc",
    query: { enabled: isConnected },
  });
  const usdcAddress = (usdcAddressData as Address | undefined) ?? ("" as Address);

  // Shared between AuthorizeTab (input), RevokeTab (read-only), History,
  // and Export tabs — RevokeTab intentionally has no input of its own.
  const [agent, setAgent] = useState("");
  const [shareReceiver, setShareReceiver] = useState("");

  const { gatewayVerificationState, registrationMode = false } = props;
  const ctx: PreviewContext = {
    gateway: props.gatewayAddress,
    gatewayCodeHashVerified: gatewayVerificationState.status === "verified",
    envClass: props.envClass,
  };

  const tabs = buildAdminTabs({
    gatewayAddress: props.gatewayAddress,
    vaultAddress: props.vaultAddress,
    usdcAddress,
    chainId,
    ctx,
    gatewayVerificationState,
    flagEnv: props.flagEnv,
    historyPaneEnabled: flags.historyPane,
    registrationMode,
    agent,
    setAgent,
    shareReceiver,
    setShareReceiver,
  });

  return (
    <main className="admin-flow">
      <h1>{registrationMode ? "Authorize your first agent" : "Agents"}</h1>
      {registrationMode && (
        <p className="hint" data-testid="registration-hint">
          Authorize an agent to unlock the full agents panel (revoke, rotation, roles, history,
          export).
        </p>
      )}

      {gatewayVerificationState.status === "verified" && (
        <p data-testid="gateway-verification-ok" className="verification-ok">
          Gateway bytecode verified: <code>{gatewayVerificationState.computedHash}</code>
        </p>
      )}

      {flags.browserGeneratedCredential ? (
        <section data-testid="browser-keygen" className="unsafe-banner">
          <strong>UNSAFE: software-backed credential</strong>
          <p>Browser-generated keypair flow ENABLED. Fork/devnet only.</p>
        </section>
      ) : (
        <p data-testid="browser-keygen-disabled" hidden>
          Browser-generated credential flow disabled.
        </p>
      )}

      <Tabs tabs={tabs} />
    </main>
  );
}
