/**
 * Canonical: docs/technical/dapp-browser-keygen-review.md §7–§8
 *
 * Tests for the browser-keygen credential path.
 *
 * These tests verify:
 *   1. The production chain guard fires before any key material is generated.
 *   2. The exported TOML contains unsafe_for_production = true.
 *   3. The exported filename includes -DEVNET-UNSAFE.
 *   4. The private key does NOT appear in any localStorage/sessionStorage write.
 *   5. clearKeygenResult zeroes the TOML config from the result object.
 *
 * ADR §8 automated checks:
 *   - Label test: assert unsafe_for_production: true in TOML output (see test 2).
 *   - Grep sentinel: the source file is checked by CI for storage writes
 *     (see .github/workflows/ci.yml keygen-sentinel job).
 */

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { isDevnetChain, isBrowserKeygenAvailable, PRODUCTION_CHAIN_IDS } from "../src/config.js";

// --- config.ts unit tests ---------------------------------------------------

describe("isDevnetChain", () => {
  it("returns true for anvil chain id 31337", () => {
    expect(isDevnetChain(31337n)).toBe(true);
  });

  it("returns false for all production chain ids", () => {
    for (const id of PRODUCTION_CHAIN_IDS) {
      expect(isDevnetChain(id)).toBe(false);
    }
  });

  it("returns false for Base mainnet 8453", () => {
    expect(isDevnetChain(8453n)).toBe(false);
  });

  it("returns false for Ethereum mainnet 1", () => {
    expect(isDevnetChain(1n)).toBe(false);
  });
});

describe("isBrowserKeygenAvailable", () => {
  it("returns false for production chains regardless of flag", () => {
    // DAPP_BROWSER_KEYGEN_ENABLED defaults to false in tests (no env var set)
    for (const id of PRODUCTION_CHAIN_IDS) {
      expect(isBrowserKeygenAvailable(id)).toBe(false);
    }
  });
});

// --- keygen.ts unit tests ---------------------------------------------------
// We import the module dynamically so the test suite can mock window.crypto.

describe("generateBrowserCredential", () => {
  beforeEach(() => {
    // Mock window.crypto.getRandomValues with deterministic test bytes.
    // The 32-byte value below is anvil account #0's private key — only used
    // as a deterministic fixture; never a real secret in this test context.
    const fixedBytes = new Uint8Array([
      0xac, 0x09, 0x74, 0xbe, 0xc3, 0x9a, 0x17, 0xe3,
      0x6b, 0xa4, 0xa6, 0xb4, 0xd2, 0x38, 0xff, 0x94,
      0x4b, 0xac, 0xb4, 0x78, 0xcb, 0xed, 0x5e, 0xfc,
      0xae, 0x78, 0x4d, 0x7b, 0xf4, 0xf2, 0xff, 0x80,
    ]);
    vi.stubGlobal("crypto", {
      getRandomValues: (buf: Uint8Array) => {
        buf.set(fixedBytes.slice(0, buf.length));
        return buf;
      },
    });
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("refuses production chain ids before generating any key material", async () => {
    const { generateBrowserCredential } = await import("../src/keygen.js");
    for (const id of PRODUCTION_CHAIN_IDS) {
      await expect(
        generateBrowserCredential(id, "http://production-rpc"),
      ).rejects.toThrow(/production chain/i);
    }
  });

  it("refuses Base mainnet chain id 8453", async () => {
    const { generateBrowserCredential } = await import("../src/keygen.js");
    await expect(
      generateBrowserCredential(8453n, "http://base-mainnet"),
    ).rejects.toThrow(/8453/);
  });

  it("generates a result for a devnet chain id", async () => {
    const { generateBrowserCredential } = await import("../src/keygen.js");
    const result = await generateBrowserCredential(31337n, "http://127.0.0.1:8545");
    expect(result.address).toMatch(/^0x[0-9a-fA-F]{40}$/);
    expect(result.tomlConfig).toBeTruthy();
    expect(result.filename).toBeTruthy();
  });

  it("exported TOML contains unsafe_for_production = true (ADR §5 label test)", async () => {
    const { generateBrowserCredential } = await import("../src/keygen.js");
    const result = await generateBrowserCredential(31337n, "http://127.0.0.1:8545");
    expect(result.tomlConfig).toContain("unsafe_for_production = true");
  });

  it("exported TOML contains [signer] section", async () => {
    const { generateBrowserCredential } = await import("../src/keygen.js");
    const result = await generateBrowserCredential(31337n, "http://127.0.0.1:8545");
    expect(result.tomlConfig).toContain("[signer]");
  });

  it("exported TOML contains [network] section with chain_id", async () => {
    const { generateBrowserCredential } = await import("../src/keygen.js");
    const result = await generateBrowserCredential(31337n, "http://127.0.0.1:8545");
    expect(result.tomlConfig).toContain("[network]");
    expect(result.tomlConfig).toContain("chain_id = 31337");
  });

  it("exported filename includes -DEVNET-UNSAFE suffix (ADR §5)", async () => {
    const { generateBrowserCredential } = await import("../src/keygen.js");
    const result = await generateBrowserCredential(31337n, "http://127.0.0.1:8545");
    expect(result.filename).toContain("-DEVNET-UNSAFE");
    expect(result.filename).toMatch(/\.toml$/);
  });

  it("clearKeygenResult zeroes the tomlConfig (key no longer accessible)", async () => {
    const { generateBrowserCredential, clearKeygenResult } = await import("../src/keygen.js");
    const result = await generateBrowserCredential(31337n, "http://127.0.0.1:8545");
    expect(result.tomlConfig).not.toBe("");
    clearKeygenResult(result);
    expect(result.tomlConfig).toBe("");
  });

  it("clearKeygenResult retains the public address", async () => {
    const { generateBrowserCredential, clearKeygenResult } = await import("../src/keygen.js");
    const result = await generateBrowserCredential(31337n, "http://127.0.0.1:8545");
    const addr = result.address;
    clearKeygenResult(result);
    expect(result.address).toBe(addr);
  });
});

// --- localStorage sentinel --------------------------------------------------
// Verifies that no storage write occurs during keygen.
// This is the automated check from ADR §8 item 1 (grep sentinel complement).

describe("key-custody: no localStorage or sessionStorage writes during keygen", () => {
  beforeEach(() => {
    vi.stubGlobal("crypto", {
      getRandomValues: (buf: Uint8Array) => {
        buf.fill(0xab); // any non-zero deterministic bytes
        return buf;
      },
    });
    // Spy on storage setItem to detect any write.
    vi.spyOn(Storage.prototype, "setItem");
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("does not call localStorage.setItem during keygen", async () => {
    const { generateBrowserCredential } = await import("../src/keygen.js");
    await generateBrowserCredential(31337n, "http://127.0.0.1:8545").catch(() => {});
    expect(Storage.prototype.setItem).not.toHaveBeenCalled();
  });
});
