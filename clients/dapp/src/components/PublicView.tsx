/**
 * PublicView — non-admin user surface. Deposit/withdraw forms,
 * live status dashboard, and per-agent deposit history.
 *
 * Deposit/withdraw require a vault ABI that is not yet present in
 * src/lib/abi.ts; the buttons stay disabled with a `TODO` marker
 * until that ABI lands. The dashboard sections wire to the existing
 * gateway ABI.
 */
import { useState } from "react";
import { useAccount, useConnect, useDisconnect, useChainId, useReadContract } from "wagmi";
import { isAddress, type Address } from "viem";
import { gatewayAbi } from "../lib/abi";
import { HistoryPane } from "./HistoryPane";
import { resolveExplorerApiUrl } from "../lib/explorerApi";
import { resolveFlags } from "../lib/featureFlags";

interface PublicViewProps {
  gatewayAddress: Address;
  vaultAddress: Address;
  envClass: "fork" | "devnet" | "testnet" | "mainnet";
  flagEnv: Record<string, string | undefined>;
}

export function PublicView(props: PublicViewProps) {
  const flags = resolveFlags(props.flagEnv);
  const { address, isConnected } = useAccount();
  const { connect, connectors } = useConnect();
  const { disconnect } = useDisconnect();
  const chainId = useChainId();

  const { data: pausedData } = useReadContract({
    address: props.gatewayAddress,
    abi: gatewayAbi,
    functionName: "paused",
    query: { enabled: isConnected },
  });
  const paused = Boolean(pausedData);

  const { data: usdcAddressData } = useReadContract({
    address: props.gatewayAddress,
    abi: gatewayAbi,
    functionName: "usdc",
    query: { enabled: isConnected },
  });
  const usdcAddress = (usdcAddressData as Address | undefined) ?? "";

  const [depositAmount, setDepositAmount] = useState("");
  const [withdrawAmount, setWithdrawAmount] = useState("");
  const [historyAgent, setHistoryAgent] = useState("");
  const validHistoryAgent = isAddress(historyAgent);

  return (
    <main className="public-view">
      <section className="hero" data-testid="hero">
        <p className="hero-eyebrow">{props.envClass.toUpperCase()}</p>
        <h1>One USDC transfer. Diversified exposure.</h1>
        <p className="hero-sub">
          Deposit USDC into the RobotMoney gateway. The agent allocates across the bucket portfolio
          and returns shares.
        </p>
      </section>

      <section data-testid="connect-section">
        {!isConnected ? (
          <>
            <h2>Connect</h2>
            <p>Connect a wallet to deposit, withdraw, or view your position.</p>
            {connectors.map((c) => (
              <button
                key={c.uid}
                data-testid={`connect-${c.id}`}
                onClick={() => connect({ connector: c })}
              >
                Connect {c.name}
              </button>
            ))}
            {connectors.length === 0 && (
              <p data-testid="no-connectors">
                No browser wallet detected. Install a wallet extension to continue.
              </p>
            )}
          </>
        ) : (
          <>
            <h2>Connected</h2>
            <p>
              <code data-testid="connected-address">{address}</code>
            </p>
            <button data-testid="disconnect" onClick={() => disconnect()}>
              Disconnect
            </button>
          </>
        )}
      </section>

      <section className="stat-grid" data-testid="status-grid">
        <div className="stat-card">
          <p className="stat-label">Chain</p>
          <p className="stat-value">{isConnected ? chainId : "—"}</p>
        </div>
        <div className="stat-card">
          <p className="stat-label">Gateway</p>
          <p className="stat-value font-mono">{shortAddr(props.gatewayAddress)}</p>
        </div>
        <div className="stat-card">
          <p className="stat-label">Vault</p>
          <p className="stat-value font-mono">{shortAddr(props.vaultAddress)}</p>
        </div>
        <div className="stat-card">
          <p className="stat-label">USDC</p>
          <p className="stat-value font-mono">{usdcAddress ? shortAddr(usdcAddress) : "—"}</p>
        </div>
        <div className="stat-card">
          <p className="stat-label">Status</p>
          <p
            className="stat-value"
            data-testid="public-paused"
            style={{ color: paused ? "var(--color-warn)" : "var(--color-accent)" }}
          >
            {isConnected ? (paused ? "PAUSED" : "ACTIVE") : "—"}
          </p>
        </div>
      </section>

      <div className="form-grid">
        <section data-testid="deposit-form">
          <h2>Deposit</h2>
          <p>Send USDC to the gateway. Receive vault shares.</p>
          <label>
            Amount (USDC)
            <input
              data-testid="deposit-amount"
              value={depositAmount}
              onChange={(e) => setDepositAmount(e.target.value)}
              placeholder="0.00"
            />
          </label>
          {/* TODO: vault ABI not yet wired — see src/lib/abi.ts */}
          <button data-testid="deposit-submit" disabled>
            Sign deposit with wallet
          </button>
          <p className="hint">Vault integration pending.</p>
        </section>

        <section data-testid="withdraw-form">
          <h2>Withdraw</h2>
          <p>Burn shares. Receive USDC.</p>
          <label>
            Shares
            <input
              data-testid="withdraw-amount"
              value={withdrawAmount}
              onChange={(e) => setWithdrawAmount(e.target.value)}
              placeholder="0.00"
            />
          </label>
          <button data-testid="withdraw-submit" disabled>
            Sign withdraw with wallet
          </button>
          <p className="hint">Vault integration pending.</p>
        </section>
      </div>

      {flags.historyPane && (
        <section data-testid="public-history">
          <h2>Deposit history</h2>
          <label>
            Agent address
            <input
              data-testid="history-agent-input"
              value={historyAgent}
              onChange={(e) => setHistoryAgent(e.target.value)}
              placeholder="0x..."
            />
          </label>
          {validHistoryAgent && (
            <HistoryPane
              agent={historyAgent as Address}
              apiUrl={resolveExplorerApiUrl(props.flagEnv)}
            />
          )}
        </section>
      )}
    </main>
  );
}

function shortAddr(a: string): string {
  if (!a || a === "0x0000000000000000000000000000000000000000") return "—";
  return `${a.slice(0, 6)}…${a.slice(-4)}`;
}
