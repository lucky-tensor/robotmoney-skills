/**
 * AdminFlow — orchestrates the agent-management tabs. Each tab owns
 * its wallet hooks and preview pipeline; this component only routes
 * shared state (agent address, share receiver) between tabs that
 * reference them and assembles the visible tab list.
 *
 * The admin is the connected wallet (human admin role). The agent
 * address is supplied by the operator (register-only flow per ADR §3.1).
 * Browser-generated keypair flow is gated by featureFlags.
 */
import { useState } from "react";
import { useAccount, useChainId, useReadContract } from "wagmi";
import { isAddress, type Address } from "viem";
import { gatewayAbi } from "../lib/abi";
import type { PreviewContext } from "../lib/preview";
import { ConfigExportPanel } from "./ConfigExportPanel";
import { HistoryPane } from "./HistoryPane";
import { PauseFlow } from "./PauseFlow";
import { Tabs, type TabDef } from "./Tabs";
import { resolveFlags } from "../lib/featureFlags";
import { resolveExplorerApiUrl } from "../lib/explorerApi";
import type { VerificationState } from "../lib/useGatewayVerifier";
import { AuthorizeTab } from "./admin/AuthorizeTab";
import { RevokeTab } from "./admin/RevokeTab";
import { RotationTab } from "./admin/RotationTab";
import { RoleTab } from "./admin/RoleTab";
import { DepositWithdrawTab } from "./admin/DepositWithdrawTab";

interface AdminFlowProps {
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
}

export function AdminFlow(props: AdminFlowProps) {
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

  const validAgent = isAddress(agent);
  const validReceiver = isAddress(shareReceiver);

  const { gatewayVerificationState, registrationMode } = props;
  const gatewayCodeHashVerified = gatewayVerificationState.status === "verified";

  const ctx: PreviewContext = {
    gateway: props.gatewayAddress,
    gatewayCodeHashVerified,
    envClass: props.envClass,
  };

  const tabs: TabDef[] = [
    {
      id: "authorize",
      label: "Authorize",
      content: (
        <AuthorizeTab
          gatewayAddress={props.gatewayAddress}
          ctx={ctx}
          agent={agent}
          setAgent={setAgent}
          shareReceiver={shareReceiver}
          setShareReceiver={setShareReceiver}
        />
      ),
    },
  ];

  if (!registrationMode) {
    tabs.push(
      {
        id: "deposit-withdraw",
        label: "Deposit & Withdraw",
        content: <DepositWithdrawTab />,
      },
      {
        id: "pause",
        label: "Pause",
        content: (
          <PauseFlow
            gatewayAddress={props.gatewayAddress}
            gatewayCodeHashVerified={gatewayCodeHashVerified}
            envClass={props.envClass}
          />
        ),
      },
      {
        id: "revoke",
        label: "Revoke",
        content: <RevokeTab gatewayAddress={props.gatewayAddress} ctx={ctx} agent={agent} />,
      },
      {
        id: "rotation",
        label: "Rotation",
        content: <RotationTab gatewayAddress={props.gatewayAddress} ctx={ctx} />,
      },
      {
        id: "admin-role",
        label: "Admin Role",
        content: (
          <RoleTab
            role="ADMIN_ROLE"
            gatewayAddress={props.gatewayAddress}
            ctx={ctx}
            description={
              <p>
                Mutually exclusive with AGENT_ROLE and PAUSER_ROLE per
                <code> AccessRoles._grantRole</code>. Only DEFAULT_ADMIN_ROLE holders may grant.
              </p>
            }
          />
        ),
      },
      {
        id: "pauser-role",
        label: "Pauser Role",
        content: (
          <RoleTab
            role="PAUSER_ROLE"
            gatewayAddress={props.gatewayAddress}
            ctx={ctx}
            description={
              <p>
                PAUSER may call <code>pause()</code> only; <code>unpause()</code> requires
                ADMIN_ROLE. Mutually exclusive with AGENT_ROLE and ADMIN_ROLE on the same account.
              </p>
            }
          />
        ),
      },
    );

    if (flags.historyPane && validAgent) {
      tabs.push({
        id: "history",
        label: "History",
        content: (
          <HistoryPane agent={agent as Address} apiUrl={resolveExplorerApiUrl(props.flagEnv)} />
        ),
      });
    }

    if (validAgent && validReceiver) {
      tabs.push({
        id: "export",
        label: "Export Config",
        content: (
          <ConfigExportPanel
            gateway={props.gatewayAddress}
            vault={props.vaultAddress}
            usdcAddress={usdcAddress}
            gatewayRuntimeHash={
              gatewayVerificationState.status === "verified"
                ? gatewayVerificationState.computedHash
                : ""
            }
            chainId={chainId}
            rpcUrl={props.flagEnv.VITE_FORK_RPC_URL ?? "http://127.0.0.1:8545"}
            agent={agent as Address}
          />
        ),
      });
    }
  }

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
