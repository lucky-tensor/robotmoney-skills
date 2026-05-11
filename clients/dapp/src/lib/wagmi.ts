/**
 * wagmi/viem client setup. The dapp uses the browser-injected EIP-1193
 * provider (MetaMask, hardware bridges, etc.) as its only wallet
 * connector AND as its read transport for the foundry/devnet chain —
 * see `docs/security/dapp-topology.md` §2 ("No dapp-owned RPC"). All
 * traffic for the chain the user is interacting with traverses an
 * endpoint the user chose, not one this bundle was built with.
 * Test harnesses inject `window.ethereum` themselves before the page
 * loads — no test-only branches in this file.
 */
import { unstable_connector, http, createConfig } from "wagmi";
import { foundry, mainnet, sepolia } from "wagmi/chains";
import { injected } from "wagmi/connectors";
import { defineChain } from "viem";

// Robot Money devnet (Geth+Lighthouse fork). Real prod-shaped chain id;
// not the same as foundry/anvil (31337). Used by the smoke-test stack
// and any hosted devnet. RPC URL is intentionally empty here — the
// dapp never builds an HTTP transport for this chain, see §2 of
// docs/security/dapp-topology.md.
const devnet = defineChain({
  id: 32382,
  name: "Robot Money devnet",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [] } },
});

export function makeConfig(_env: Record<string, string | undefined>) {
  return createConfig({
    chains: [devnet, foundry, sepolia, mainnet],
    connectors: [injected()],
    transports: {
      [devnet.id]: unstable_connector(injected),
      [foundry.id]: unstable_connector(injected),
      [sepolia.id]: http(),
      [mainnet.id]: http(),
    },
  });
}
