import { defineConfig } from "@playwright/test";

// Playwright config for the human-dapp E2E flows.
//
// Default mode (no special env):
//   The fork-anvil sidecar is started by CI (.github/workflows/dapp.yml) or
//   the developer ahead of time; the dapp itself reads RPC URL from the
//   VITE_FORK_RPC_URL env var. Locally, run:
//
//     anvil --fork-url $RMPC_FORK_RPC_URL --port 8545 &
//     bun run test:e2e
//
// Full-stack devnet mode (DEVNET_E2E_ENABLED=1):
//   devnet-global-setup.ts spawns `cargo run -p smoke-test -- --full-stack`,
//   parses the endpoint summary printed to stdout, and writes the addresses to a
//   temp JSON file. The devnet tests read that file and navigate to the
//   randomized dapp_url directly. globalTeardown kills the process, which
//   triggers Drop teardown of both compose stacks. No shell harness script is
//   needed.
//
//   Run with:
//     DEVNET_E2E_ENABLED=1 bun run test:e2e -- devnet-e2e.spec.ts
//
// We do not optimize for fast feedback here; per the user memory
// "no fast-feedback optimization in test harness" we boot a real chain
// rather than a mocked transport.

const DEVNET_E2E = process.env.DEVNET_E2E_ENABLED === "1";

export default defineConfig({
  testDir: "./tests/e2e",
  // Devnet tests can take longer: real block times (~12s) + boot overhead.
  timeout: DEVNET_E2E ? 180_000 : 60_000,
  expect: { timeout: DEVNET_E2E ? 30_000 : 10_000 },
  fullyParallel: false,
  retries: 0,
  reporter: [["list"], ["html", { open: "never" }]],

  // Conditionally load globalSetup/globalTeardown for devnet mode.
  ...(DEVNET_E2E
    ? {
        globalSetup: "./tests/e2e/devnet-global-setup.ts",
        globalTeardown: "./tests/e2e/devnet-global-teardown.ts",
      }
    : {}),
  use: {
    baseURL: "http://127.0.0.1:5173",
    trace: "retain-on-failure",
    screenshot: "on",
  },

  ...(DEVNET_E2E
    ? {}
    : {
        // Use the production preview server in CI: it does not need a
        // long Vite dev-server warmup, which on slow CI runners blows
        // through the default 60s timeout. Locally we still spin up the
        // dev server for fast iteration.
        webServer: {
          command: process.env.CI
            ? "bun run build && bunx vite preview --port 5173 --host 127.0.0.1"
            : "bun run dev",
          url: "http://127.0.0.1:5173",
          reuseExistingServer: !process.env.CI,
          timeout: 180_000,
        },
      }),
});
