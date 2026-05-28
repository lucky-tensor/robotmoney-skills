// SPDX-License-Identifier: MIT
// Canonical: docs/prd.md §11 — Vault Catalog; docs/architecture.md §4.2 — Portfolio Router
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console2} from "forge-std/console2.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {RobotMoneyVault} from "../RobotMoneyVault.sol";
import {VaultRegistry} from "../VaultRegistry.sol";
import {PortfolioRouter} from "../PortfolioRouter.sol";
import {AgentTokenVault} from "../vaults/AgentTokenVault.sol";
import {ProtocolAssetVault} from "../vaults/ProtocolAssetVault.sol";
import {ISwapRouter} from "../interfaces/ISwapRouter.sol";

/// @notice Demo-only stand-in ERC20 for the basket-vault devnet seeds. The
///         devnet has no real liquidity for the PRD §11.2 protocol basket
///         (wETH, cbBTC, wSOL) or the §11.3 agent shortlist; this fills both
///         baskets so `BasketVault.addAsset` can wire entries and the dapp can
///         enumerate them. Never deployed on mainnet (this script is demo-only).
contract DemoBasketToken is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}
}

/// @notice Minimal Uniswap V3 pool stub exposing only `token0()`/`token1()`,
///         the two reads `BasketVault.addAsset` uses to verify a pool pairs the
///         basket token with USDC. Demo-only; no swap/observe liquidity.
contract DemoUsdcPool {
    address public immutable token0;
    address public immutable token1;

    constructor(address tokenA, address tokenB) {
        // Order is irrelevant to addAsset's check; store as given.
        token0 = tokenA;
        token1 = tokenB;
    }
}

/// @notice One-shot batch deployer for the AgentTokenVault devnet basket
///         stand-ins (PRD §11.3). Its constructor performs all 12 sub-`CREATE`s
///         (six `DemoBasketToken` + six `DemoUsdcPool`) in a single broadcaster
///         transaction. The script then makes one `vault.addAsset(...)` call
///         per token. Collapses the per-symbol broadcast loop from 18 tx
///         (6 × token + pool + addAsset) down to 7, keeping smoke-test
///         chain-boot inside the dapp-e2e `globalSetup` budget on GH-hosted
///         runners. Demo-only.
contract AgentBasketStubDeployer {
    DemoBasketToken[6] public tokens;
    DemoUsdcPool[6] public pools;

    constructor(string[6] memory symbols, address usdc) {
        for (uint256 i = 0; i < symbols.length; i++) {
            DemoBasketToken token =
                new DemoBasketToken(string.concat("Demo Agent ", symbols[i]), symbols[i]);
            tokens[i] = token;
            pools[i] = new DemoUsdcPool(address(token), usdc);
        }
    }
}

/// @notice One-shot batch deployer for the ProtocolAssetVault devnet basket
///         stand-ins (PRD §11.2 — wETH, cbBTC, wSOL). Mirrors the
///         `AgentBasketStubDeployer` shape: 6 sub-CREATEs (3 stand-in tokens
///         + 3 USDC pool stubs) in a single broadcaster CREATE. Demo-only.
contract ProtocolBasketStubDeployer {
    DemoBasketToken[3] public tokens;
    DemoUsdcPool[3] public pools;

    constructor(string[3] memory symbols, address usdc) {
        for (uint256 i = 0; i < symbols.length; i++) {
            DemoBasketToken token =
                new DemoBasketToken(string.concat("Demo Protocol ", symbols[i]), symbols[i]);
            tokens[i] = token;
            pools[i] = new DemoUsdcPool(address(token), usdc);
        }
    }
}

/// @notice Batch deployer #1 — the canonical `ProtocolAssetVault` (PRD §11.2)
///         deployed inside a single broadcaster CREATE. Constructed with
///         admin = adminAddr (the script broadcaster) so subsequent
///         `addAsset` + registry calls remain on the broadcast key. Demo-only.
contract ProtocolVaultBatchDeployer {
    ProtocolAssetVault public immutable protocolVault;

    constructor(
        address usdc,
        address adminAddr,
        address swapRouter,
        uint256 tvlCap,
        uint256 perDepositCap
    ) {
        protocolVault = new ProtocolAssetVault(
            IERC20(usdc), ISwapRouter(swapRouter), tvlCap, perDepositCap, 0, adminAddr, adminAddr
        );
    }
}

/// @notice Batch deployer #2 — the RWA/Thematic placeholder vault (PRD §11.4)
///         plus the `AgentTokenVault` (PRD §11.3). Performs two direct
///         sub-CREATEs inside a single broadcaster CREATE. Kept separate
///         from `ProtocolVaultBatchDeployer` so combined initcode stays under
///         EIP-3860's 49152-byte limit (geth enforces this on the smoke-test
///         devnet). All vaults constructed with admin = adminAddr. Demo-only.
contract DemoAgentRwaBatchDeployer {
    RobotMoneyVault public immutable rwaVault;
    AgentTokenVault public immutable agentVault;

    constructor(
        address usdc,
        address adminAddr,
        address swapRouter,
        uint256 tvlCap,
        uint256 perDepositCap
    ) {
        rwaVault = new RobotMoneyVault(IERC20(usdc), tvlCap, perDepositCap, 0, adminAddr, adminAddr);
        agentVault = new AgentTokenVault(
            IERC20(usdc), ISwapRouter(swapRouter), tvlCap, perDepositCap, 0, adminAddr, adminAddr
        );
    }
}

/// @title DeployDemoExtraVaults
/// @notice Demo-only deploy script that aligns the devnet vault set with the
///         four-vault PRD §11 catalog: Stable Yield (deployed by Deploy.s.sol),
///         Protocol Asset, Agent Token, and an RWA/Thematic placeholder.
///         Registers all three additions in `VaultRegistry`, seeds the two
///         basket vaults with devnet stand-in tokens, and resets the router
///         weight vector to a three-way split across the three Active vaults.
///
///         Why this exists: to exercise the full PRD vault catalog end to end
///         (Portfolio Explorer, /v1/vaults TVL, Router Governance weights) the
///         demo seed deploys the same vault classes the PRD names — no generic
///         stand-in clones. `ProtocolAssetVault` and `AgentTokenVault` carry
///         devnet basket stubs; `RobotMoneyVault` is reused as the RWA
///         placeholder (Paused, never router-eligible) because PRD §11.4 marks
///         that vault as Future / not specified — no canonical contract.
///
///         Router eligibility: production status per PRD §11.2 and §11.3 marks
///         the basket vaults as "Prototype — not Router-eligible". The demo
///         seed *intentionally* overrides this on the devnet registry by
///         calling `setRouterEligible(true)` on the Protocol and Agent vaults
///         so the multi-vault Router Governance UI has three Active legs to
///         display. This is registry state, not a code variant — production
///         keeps the vaults router-ineligible by simply never running this
///         script (single-production-codebase, see
///         `docs/development/single-production-codebase.md`).
///
///         Required env vars:
///           ADMIN_ADDRESS      — receives ADMIN_ROLE on the new vaults and
///                                must already hold ADMIN_ROLE on
///                                VaultRegistry + PortfolioRouter
///           REGISTRY_ADDRESS   — deployed VaultRegistry
///           ROUTER_ADDRESS     — deployed PortfolioRouter
///           PRIMARY_VAULT      — RobotMoneyVault deployed by Deploy.s.sol
///                                (kept in the weight vector with the largest
///                                share)
///           USDC_ADDRESS       — ERC-20 asset every vault denominates in
///           WEIGHT_PRIMARY_BPS — bps for PRIMARY_VAULT in the new vector
///           WEIGHT_EXTRA1_BPS  — bps for ProtocolAssetVault
///           WEIGHT_EXTRA2_BPS  — bps for AgentTokenVault
///                                (the three must sum to 10 000)
///
///         Optional env vars:
///           SWAP_ROUTER        — Uniswap V3 SwapRouter02 address for the
///                                basket vaults (defaults to Base mainnet)
///           RWA_VAULT_NAME     — registry name for the RWA/Thematic
///                                placeholder
///                                (default: "Robot Money RWA / Thematic")
///           DEPLOYMENT_OUT     — output JSON path
///                                (default: "deployments/demo-extra-vaults-<chain_id>.json")
contract DeployDemoExtraVaults is Script {
    using stdJson for string;

    /// @notice Result struct returned to in-process callers (e.g. forge tests).
    struct Deployed {
        /// @dev `ProtocolAssetVault` (PRD §11.2). Registered Active and made
        ///      router-eligible for the demo (override of the production
        ///      "not Router-eligible" status).
        address protocolVault;
        /// @dev Devnet stand-in ERC20 addresses seeded into ProtocolAssetVault.
        address[] protocolTokens;
        /// @dev `AgentTokenVault` (PRD §11.3). Registered Active and made
        ///      router-eligible for the demo (override of the production
        ///      "not Router-eligible" status).
        address agentTokenVault;
        /// @dev Devnet stand-in ERC20 addresses seeded into AgentTokenVault
        ///      (six MVP shortlist symbols, ADR-0001).
        address[] agentTokens;
        /// @dev RWA/Thematic placeholder (PRD §11.4). Registered non-Active
        ///      (Paused) and never router-eligible; not in the weight vector.
        address rwaVault;
        uint256 weightPrimaryBps;
        uint256 weightProtocolBps;
        uint256 weightAgentBps;
    }

    /// @notice Canonical MVP AgentTokenVault shortlist symbols, in deploy order
    ///         (docs/adr/ADR-0001-mvp-agent-token-shortlist.md). PEAQ excluded.
    string[6] internal AGENT_SYMBOLS = ["JUNO", "ROBOTMONEY", "BANKR", "ZYFAI", "GIZA", "DEUS"];
    /// @notice Default swap fee tier for demo stand-in pools (agent tokens are
    ///         illiquid; matches AgentTokenVault's 3% default-slippage stance).
    uint24 internal constant DEMO_AGENT_SWAP_FEE = 10_000;

    /// @notice ProtocolAssetVault basket symbols (PRD §11.2 — wETH, cbBTC, wSOL).
    string[3] internal PROTOCOL_SYMBOLS = ["wETH", "cbBTC", "wSOL"];
    /// @notice Swap fee tier for the protocol-asset basket stubs (mainnet wETH
    ///         pools commonly use 0.05%; matches the 1% default-slippage stance
    ///         on `ProtocolAssetVault` headroom).
    uint24 internal constant DEMO_PROTOCOL_SWAP_FEE = 500;

    /// @notice Default human-readable name for the RWA/Thematic placeholder
    ///         (PRD §11.4). Future / not-specified vault category.
    string public constant DEFAULT_RWA_NAME = "Robot Money RWA / Thematic";

    /// @notice TVL cap mirrored from Deploy.s.sol (10M USDC) — demo vaults
    ///         carry the same caps as the primary so the harness can fund any
    ///         scenario without per-vault tuning.
    uint256 public constant DEMO_TVL_CAP = 10_000_000 * 1e6;
    /// @notice Per-deposit cap mirrored from Deploy.s.sol (1M USDC).
    uint256 public constant DEMO_PER_DEPOSIT_CAP = 1_000_000 * 1e6;

    /// @dev Env-derived params bundled to keep `run()` locals below the
    ///      Solidity stack limit (16 slots, ~stack-too-deep).
    struct Params {
        address admin;
        address registry;
        address router;
        address primaryVault;
        address usdc;
        // Uniswap V3 SwapRouter02 for the basket vaults. On devnet no swaps run
        // during seed (only addAsset + register), so a non-functional address
        // is acceptable; defaults to the Base mainnet SwapRouter02.
        address swapRouter;
        uint256 wPrimary;
        uint256 wProtocol;
        uint256 wAgent;
        string rwaName;
    }

    /// @notice Base mainnet Uniswap V3 SwapRouter02 — default basket-vault swap
    ///         router when SWAP_ROUTER is unset (mirrors the basket vaults).
    address internal constant DEFAULT_SWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;

    /// @notice Forge broadcast entrypoint. Deploys ProtocolAssetVault,
    ///         AgentTokenVault, the RWA placeholder; registers all three;
    ///         seeds the two basket vaults; resets the router weight vector.
    function run() external returns (Deployed memory d) {
        Params memory p = _readParams();

        vm.startBroadcast();
        d = _doDeploy(p);
        vm.stopBroadcast();

        _writeDeploymentJson(d);
        _logResult(d);
    }

    /// @notice In-process entrypoint for forge tests. Runs the same deploy +
    ///         seed body as `run()` but without `vm.startBroadcast`, so the
    ///         caller (the test contract) is the broadcaster and must already
    ///         hold ADMIN_ROLE on the registry and router. No deployment JSON
    ///         is written.
    /// @param p Fully-formed params (no env reads).
    function runInProcess(Params memory p) external returns (Deployed memory d) {
        require(p.wPrimary + p.wProtocol + p.wAgent == 10_000, "weights must sum to 10000");
        require(p.wPrimary > 0 && p.wProtocol > 0 && p.wAgent > 0, "weights must be non-zero");
        d = _doDeploy(p);
    }

    function _readParams() internal view returns (Params memory p) {
        p.admin = vm.envAddress("ADMIN_ADDRESS");
        p.registry = vm.envAddress("REGISTRY_ADDRESS");
        p.router = vm.envAddress("ROUTER_ADDRESS");
        p.primaryVault = vm.envAddress("PRIMARY_VAULT");
        p.usdc = vm.envAddress("USDC_ADDRESS");
        p.swapRouter = _envAddressOrDefault("SWAP_ROUTER", DEFAULT_SWAP_ROUTER);
        p.wPrimary = vm.envUint("WEIGHT_PRIMARY_BPS");
        // EXTRA1/EXTRA2 env names kept for backward-compat with the smoke-test
        // Rust harness; semantically they're now Protocol and Agent.
        p.wProtocol = vm.envUint("WEIGHT_EXTRA1_BPS");
        p.wAgent = vm.envUint("WEIGHT_EXTRA2_BPS");
        p.rwaName = _envStringOrDefault("RWA_VAULT_NAME", DEFAULT_RWA_NAME);

        require(p.admin != address(0), "ADMIN_ADDRESS=0");
        require(p.registry != address(0), "REGISTRY_ADDRESS=0");
        require(p.router != address(0), "ROUTER_ADDRESS=0");
        require(p.primaryVault != address(0), "PRIMARY_VAULT=0");
        require(p.usdc != address(0), "USDC_ADDRESS=0");
        require(p.wPrimary + p.wProtocol + p.wAgent == 10_000, "weights must sum to 10000");
        require(p.wPrimary > 0 && p.wProtocol > 0 && p.wAgent > 0, "weights must be non-zero");
    }

    /// @dev Caller must hold ADMIN_ROLE on registry + router via broadcast
    ///      key. Splits the body of `run()` so the locals stay below the
    ///      stack-too-deep limit.
    function _doDeploy(Params memory p) internal returns (Deployed memory d) {
        // Batched CREATEs: four broadcaster CREATEs instead of one-per-contract.
        // The split is forced by EIP-3860 — combining all sub-CREATEs into a
        // single batcher pushes initcode past geth's 49152-byte max-initcode
        // limit. Each batcher below stays under the limit.
        ProtocolVaultBatchDeployer batchA = new ProtocolVaultBatchDeployer(
            p.usdc, p.admin, p.swapRouter, DEMO_TVL_CAP, DEMO_PER_DEPOSIT_CAP
        );
        DemoAgentRwaBatchDeployer batchB = new DemoAgentRwaBatchDeployer(
            p.usdc, p.admin, p.swapRouter, DEMO_TVL_CAP, DEMO_PER_DEPOSIT_CAP
        );
        ProtocolBasketStubDeployer protocolStubs =
            new ProtocolBasketStubDeployer(PROTOCOL_SYMBOLS, p.usdc);
        AgentBasketStubDeployer agentStubs = new AgentBasketStubDeployer(AGENT_SYMBOLS, p.usdc);

        // Stash addresses in the result struct immediately so we don't have to
        // keep all the contract handles live as locals (avoids stack-too-deep
        // across the wiring + registry + weights calls).
        d.protocolVault = address(batchA.protocolVault());
        d.rwaVault = address(batchB.rwaVault());
        d.agentTokenVault = address(batchB.agentVault());
        d.weightPrimaryBps = p.wPrimary;
        d.weightProtocolBps = p.wProtocol;
        d.weightAgentBps = p.wAgent;

        VaultRegistry registry = VaultRegistry(p.registry);

        // 1. Seed ProtocolAssetVault (PRD §11.2) basket with wETH/cbBTC/wSOL
        //    stand-ins, register it Active, make it router-eligible for the
        //    demo (override of production "not Router-eligible" status).
        d.protocolTokens =
            _seedProtocolAssetVault(ProtocolAssetVault(d.protocolVault), protocolStubs);
        _registerIfAbsent(registry, d.protocolVault, p.usdc, "Robot Money Protocol");
        registry.setRouterEligible(d.protocolVault, true);

        // 2. Seed AgentTokenVault (PRD §11.3) with the canonical MVP six-token
        //    shortlist (ADR-0001), register it Active, and make it
        //    router-eligible for the demo (override, same as Protocol).
        d.agentTokens = _seedAgentTokenVault(AgentTokenVault(d.agentTokenVault), agentStubs);
        _registerIfAbsent(registry, d.agentTokenVault, p.usdc, "Robot Money Agent Tokens");
        registry.setRouterEligible(d.agentTokenVault, true);

        // 3. Register the RWA/Thematic placeholder (PRD §11.4). Registered then
        //    immediately set to non-Active (Paused) and never router-eligible
        //    (registry default). PortfolioRouter never weights or deposits into
        //    it (not in the weight vector, isRouterEligible() == false); the
        //    dapp renders it as a Future / Coming-soon tile from on-chain
        //    status, not a hard-coded flag.
        registry.registerVault(
            d.rwaVault,
            VaultRegistry.VaultMetadata({name: p.rwaName, asset: p.usdc, registeredAt: 0})
        );
        registry.setVaultStatus(d.rwaVault, VaultRegistry.VaultStatus.Paused);

        // 4. Reset the router voted weight vector AND the on-chain default
        //    (below-quorum fallback) vector to a three-way split across the
        //    PRD §11 Active vaults (Primary + Protocol + Agent). Default vector
        //    length must match the registry's router-eligible count, so link
        //    the router on the registry first (idempotent).
        if (address(registry.router()) != p.router) {
            registry.setRouter(p.router);
        }
        _applyThreeWayWeights(
            PortfolioRouter(p.router), p.primaryVault, d.protocolVault, d.agentTokenVault, p
        );
    }

    /// @dev Wire the three PRD §11.2 basket symbols into the pre-built
    ///      `ProtocolAssetVault` via `addAsset`. Tokens + USDC pool stubs were
    ///      already created inside `ProtocolBasketStubDeployer`. The vault's
    ///      ADMIN_ROLE is held by p.admin, so addAsset succeeds on the
    ///      script broadcast key.
    function _seedProtocolAssetVault(ProtocolAssetVault vault, ProtocolBasketStubDeployer seeder)
        internal
        returns (address[] memory tokens)
    {
        tokens = new address[](PROTOCOL_SYMBOLS.length);
        for (uint256 i = 0; i < PROTOCOL_SYMBOLS.length; i++) {
            address token_ = address(seeder.tokens(i));
            address pool_ = address(seeder.pools(i));
            vault.addAsset(token_, pool_, DEMO_PROTOCOL_SWAP_FEE);
            tokens[i] = token_;
        }
    }

    /// @dev Wire the six MVP shortlist symbols into the pre-built
    ///      `AgentTokenVault` via `addAsset`. Same shape as the Protocol
    ///      basket seeding above — tokens + USDC pool stubs were already
    ///      created inside `AgentBasketStubDeployer`.
    function _seedAgentTokenVault(AgentTokenVault vault, AgentBasketStubDeployer seeder)
        internal
        returns (address[] memory tokens)
    {
        tokens = new address[](AGENT_SYMBOLS.length);
        for (uint256 i = 0; i < AGENT_SYMBOLS.length; i++) {
            address token_ = address(seeder.tokens(i));
            address pool_ = address(seeder.pools(i));
            vault.addAsset(token_, pool_, DEMO_AGENT_SWAP_FEE);
            tokens[i] = token_;
        }
    }

    /// @dev Set both the voted weight vector (used by the AC3 smoke test which
    ///      reads `getWeights()`) and the on-chain default (below-quorum
    ///      fallback, ADR-0002) to the same three-way split. Bundled into one
    ///      helper to keep the `_doDeploy` stack below the solc limit.
    function _applyThreeWayWeights(
        PortfolioRouter router,
        address primary,
        address protocol,
        address agent,
        Params memory p
    ) internal {
        _setThreeWayWeights(router, primary, protocol, agent, p);
        _setThreeWayDefaultWeights(router, primary, protocol, agent, p);
    }

    function _setThreeWayWeights(
        PortfolioRouter router,
        address primary,
        address protocol,
        address agent,
        Params memory p
    ) internal {
        address[] memory vaults = new address[](3);
        vaults[0] = primary;
        vaults[1] = protocol;
        vaults[2] = agent;
        uint256[] memory bps = new uint256[](3);
        bps[0] = p.wPrimary;
        bps[1] = p.wProtocol;
        bps[2] = p.wAgent;
        router.setWeights(vaults, bps);
    }

    /// @dev Populate the router's default (below-quorum fallback) weight vector
    ///      with the same three-way split. ADR-0002: this is the vector the
    ///      router routes by — and the allocation surface renders — with no
    ///      governance activity.
    function _setThreeWayDefaultWeights(
        PortfolioRouter router,
        address primary,
        address protocol,
        address agent,
        Params memory p
    ) internal {
        address[] memory vaults = new address[](3);
        vaults[0] = primary;
        vaults[1] = protocol;
        vaults[2] = agent;
        uint256[] memory bps = new uint256[](3);
        bps[0] = p.wPrimary;
        bps[1] = p.wProtocol;
        bps[2] = p.wAgent;
        router.setDefaultWeights(vaults, bps);
    }

    // ─── Internal ────────────────────────────────────────────────────────────

    /// @dev Register `vault` in `registry` if not already present. Returns
    ///      true if registration happened, false if already there.
    function _registerIfAbsent(
        VaultRegistry registry,
        address vault,
        address asset,
        string memory vaultName
    ) internal returns (bool registered) {
        address[] memory existing = registry.listVaults();
        for (uint256 i = 0; i < existing.length; i++) {
            if (existing[i] == vault) {
                console2.log("DeployDemoExtraVaults: vault already registered, skipping");
                return false;
            }
        }
        registry.registerVault(
            vault, VaultRegistry.VaultMetadata({name: vaultName, asset: asset, registeredAt: 0})
        );
        return true;
    }

    function _envStringOrDefault(string memory key, string memory fallback_)
        internal
        view
        returns (string memory)
    {
        try vm.envString(key) returns (string memory v) {
            if (bytes(v).length > 0) return v;
            return fallback_;
        } catch {
            return fallback_;
        }
    }

    function _envAddressOrDefault(string memory key, address fallback_)
        internal
        view
        returns (address)
    {
        try vm.envAddress(key) returns (address v) {
            if (v != address(0)) return v;
            return fallback_;
        } catch {
            return fallback_;
        }
    }

    function _logResult(Deployed memory d) internal view {
        console2.log("DeployDemoExtraVaults complete");
        console2.log("  protocolVault :", d.protocolVault);
        console2.log("  protocolTokens:", d.protocolTokens.length);
        console2.log("  agentVault    :", d.agentTokenVault);
        console2.log("  agentTokens   :", d.agentTokens.length);
        console2.log("  rwaVault      :", d.rwaVault);
        console2.log("  wPrimary      :", d.weightPrimaryBps);
        console2.log("  wProtocol     :", d.weightProtocolBps);
        console2.log("  wAgent        :", d.weightAgentBps);
    }

    function _writeDeploymentJson(Deployed memory d) internal {
        string memory outPath;
        try vm.envString("DEPLOYMENT_OUT") returns (string memory s) {
            outPath = s;
        } catch {
            outPath = string.concat(
                "deployments/demo-extra-vaults-", vm.toString(block.chainid), ".json"
            );
        }

        string memory obj = "demo_extra_vaults_deployment";
        vm.serializeUint(obj, "chain_id", block.chainid);
        vm.serializeAddress(obj, "protocol_vault", d.protocolVault);
        vm.serializeAddress(obj, "protocol_tokens", d.protocolTokens);
        vm.serializeAddress(obj, "agent_token_vault", d.agentTokenVault);
        vm.serializeAddress(obj, "agent_tokens", d.agentTokens);
        vm.serializeAddress(obj, "rwa_vault", d.rwaVault);
        vm.serializeUint(obj, "weight_primary_bps", d.weightPrimaryBps);
        vm.serializeUint(obj, "weight_protocol_bps", d.weightProtocolBps);
        string memory json = vm.serializeUint(obj, "weight_agent_bps", d.weightAgentBps);

        vm.writeJson(json, outPath);
        console2.log("Wrote demo extra vaults deployment JSON to", outPath);
    }
}
