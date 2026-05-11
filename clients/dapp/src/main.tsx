/**
 * Entry point. Reads runtime config from `import.meta.env` and bootstraps
 * the wagmi provider + AdminFlow. Vite injects `VITE_*` env vars at
 * build time so feature-flag and RPC URL knobs are reproducible per
 * deployment artefact.
 *
 * Gateway bytecode hash verification (issue #207):
 *   VITE_GATEWAY_EXPECTED_CODE_HASH must be set to the keccak256 of
 *   the expected runtime bytecode. Missing or mismatched values render
 *   refusal previews and disable every admin write button.
 */
import "./styles.css";
import React, { useEffect, useState } from "react";
import ReactDOM from "react-dom/client";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { WagmiProvider } from "wagmi";
import type { Address } from "viem";
import { AdminFlow } from "./components/AdminFlow";
import { NavBar } from "./components/NavBar";
import { PublicView } from "./components/PublicView";
import { makeConfig } from "./lib/wagmi";
import { useGatewayVerifier } from "./lib/useGatewayVerifier";

const env = import.meta.env as Record<string, string | undefined>;
const wagmiConfig = makeConfig(env);
const queryClient = new QueryClient();

const gateway = (env.VITE_GATEWAY_ADDRESS ??
  "0x0000000000000000000000000000000000000000") as Address;
const vault = (env.VITE_VAULT_ADDRESS ?? "0x0000000000000000000000000000000000000000") as Address;
const expectedCodeHash = env.VITE_GATEWAY_EXPECTED_CODE_HASH;
const envClass = (env.VITE_ENV_CLASS as "fork" | "devnet" | "testnet" | "mainnet") ?? "fork";

/**
 * Inner bootstrap component that runs inside WagmiProvider so the
 * useGatewayVerifier hook has access to the wagmi context.
 */
function App() {
  const [path, setPath] = useState(window.location.pathname);
  useEffect(() => {
    const onPop = () => setPath(window.location.pathname);
    window.addEventListener("popstate", onPop);
    return () => window.removeEventListener("popstate", onPop);
  }, []);
  const navigate = (next: string) => {
    if (next === path) return;
    window.history.pushState(null, "", next);
    setPath(next);
  };

  const verificationState = useGatewayVerifier(gateway, expectedCodeHash);
  const gatewayCodeHashVerified = verificationState.status === "verified";

  const isAdmin = path.startsWith("/admin");

  return (
    <>
      <NavBar path={isAdmin ? "/admin" : "/"} onNavigate={navigate} />
      {isAdmin ? (
        <AdminFlow
          gatewayAddress={gateway}
          vaultAddress={vault}
          gatewayCodeHashVerified={gatewayCodeHashVerified}
          gatewayVerificationState={verificationState}
          envClass={envClass}
          flagEnv={env}
        />
      ) : (
        <PublicView
          gatewayAddress={gateway}
          vaultAddress={vault}
          envClass={envClass}
          flagEnv={env}
        />
      )}
    </>
  );
}

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <App />
      </QueryClientProvider>
    </WagmiProvider>
  </React.StrictMode>,
);
