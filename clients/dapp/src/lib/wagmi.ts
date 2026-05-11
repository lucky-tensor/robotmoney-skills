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

export function makeConfig(_env: Record<string, string | undefined>) {
  return createConfig({
    chains: [foundry, sepolia, mainnet],
    connectors: [injected()],
    transports: {
      [foundry.id]: unstable_connector(injected),
      [sepolia.id]: http(),
      [mainnet.id]: http(),
    },
  });
}
