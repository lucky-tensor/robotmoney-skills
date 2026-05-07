import { defineConfig } from "@playwright/test";

// Playwright config for the human-dapp E2E flows.
//
// The fork-anvil sidecar is started by CI (.github/workflows/dapp.yml) or
// the developer ahead of time; the dapp itself reads RPC URL from the
// VITE_FORK_RPC_URL env var. Locally, run:
//
//   anvil --fork-url $RMPC_FORK_RPC_URL --port 8545 &
//   pnpm test:e2e
//
// We do not optimize for fast feedback here; per the user memory
// "no fast-feedback optimization in test harness" we boot a real anvil
// rather than a mocked transport.
export default defineConfig({
  testDir: "./tests/e2e",
  timeout: 60_000,
  expect: { timeout: 10_000 },
  fullyParallel: false,
  retries: 0,
  reporter: [["list"]],
  use: {
    baseURL: "http://127.0.0.1:5173",
    trace: "retain-on-failure",
  },
  webServer: {
    command: "pnpm dev",
    url: "http://127.0.0.1:5173",
    reuseExistingServer: !process.env.CI,
    timeout: 60_000,
  },
});
