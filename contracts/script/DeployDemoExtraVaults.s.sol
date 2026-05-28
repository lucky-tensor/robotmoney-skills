// SPDX-License-Identifier: MIT
// Canonical: docs/implementation-plan.md §"Phase: Demo seeding"; docs/architecture.md §4.2 — Portfolio Router
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console2} from "forge-std/console2.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {RobotMoneyVault} from "../RobotMoneyVault.sol";
import {VaultRegistry} from "../VaultRegistry.sol";
import {PortfolioRouter} from "../PortfolioRouter.sol";
import {PassthroughAdapter} from "../adapters/PassthroughAdapter.sol";
import {AdapterBytecodeGuard} from "./AdapterBytecodeGuard.sol";
import {AgentTokenVault} from "../vaults/AgentTokenVault.sol";
import {ISwapRouter} from "../interfaces/ISwapRouter.sol";

/// @notice Demo-only stand-in ERC20 for the AgentTokenVault shortlist. The
///         devnet has no real agent-token liquidity; this fills the basket so
///         `AgentTokenVault.shortlist()` returns the six MVP tokens for the
///         dapp. Never deployed on mainnet (DeployDemoExtraVaults is demo-only).
contract DemoAgentToken is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}
}

/// @notice Minimal Uniswap V3 pool stub exposing only `token0()`/`token1()`,
///         the two reads `BasketVault.addAsset` uses to verify a pool pairs the
///         shortlist token with USDC. Demo-only; no swap/observe liquidity.
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
///         stand-ins. Its constructor performs all 12 sub-`CREATE`s (six
///         `DemoAgentToken` + six `DemoUsdcPool`) in a single broadcaster
///         transaction. The script then makes one `vault.addAsset(...)` call
///         per token. This collapses the per-symbol broadcast loop from 18
///         transactions (6 × token + pool + addAsset) down to 7, keeping the
///         smoke-test chain-boot inside the dapp-e2e `globalSetup` budget on
///         GH-hosted runners. Demo-only; never deployed on mainnet.
contract AgentBasketStubDeployer {
    DemoAgentToken[6] public tokens;
    DemoUsdcPool[6] public pools;

    constructor(string[6] memory symbols, address usdc) {
        for (uint256 i = 0; i < symbols.length; i++) {
            DemoAgentToken token =
                new DemoAgentToken(string.concat("Demo Agent ", symbols[i]), symbols[i]);
            tokens[i] = token;
            pools[i] = new DemoUsdcPool(address(token), usdc);
        }
    }
}

/// @notice One-shot batch deployer for all CREATE-heavy demo seed contracts.
///         Its constructor performs every demo CREATE in a single broadcaster
///         transaction:
///           - 3 × `RobotMoneyVault` (extra vault1, extra vault2, RWA placeholder)
///           - 2 × `PassthroughAdapter` (one per extra vault)
///           - 1 × `AgentTokenVault` (MVP six-token basket)
///           - 1 × `AgentBasketStubDeployer` (which itself sub-CREATEs the 12
///             basket stand-ins: 6 × `DemoAgentToken` + 6 × `DemoUsdcPool`)
///         All vaults are constructed with `admin = adminAddr` so the
///         broadcaster (which the script passes in as `adminAddr`) retains
///         ADMIN_ROLE — subsequent admin calls like `vault.addAdapter`,
///         `setAdapterAllowed`, `addAsset`, registry ops still come from the
///         script's broadcast key and work unchanged. Demo-only; not deployed
///         on mainnet.
contract DemoVaultBatchDeployer {
    RobotMoneyVault public immutable vault1;
    RobotMoneyVault public immutable vault2;
    RobotMoneyVault public immutable rwaVault;
    PassthroughAdapter public immutable adapter1;
    PassthroughAdapter public immutable adapter2;
    AgentTokenVault public immutable agentVault;
    AgentBasketStubDeployer public immutable basketStubs;

    constructor(
        address usdc,
        address adminAddr,
        address swapRouter,
        uint256 tvlCap,
        uint256 perDepositCap,
        string[6] memory agentSymbols
    ) {
        vault1 = new RobotMoneyVault(IERC20(usdc), tvlCap, perDepositCap, 0, adminAddr, adminAddr);
        vault2 = new RobotMoneyVault(IERC20(usdc), tvlCap, perDepositCap, 0, adminAddr, adminAddr);
        rwaVault = new RobotMoneyVault(IERC20(usdc), tvlCap, perDepositCap, 0, adminAddr, adminAddr);
        adapter1 = new PassthroughAdapter(usdc, address(vault1));
        adapter2 = new PassthroughAdapter(usdc, address(vault2));
        agentVault = new AgentTokenVault(
            IERC20(usdc), ISwapRouter(swapRouter), tvlCap, perDepositCap, 0, adminAddr, adminAddr
        );
        basketStubs = new AgentBasketStubDeployer(agentSymbols, usdc);
    }
}

/// @title DeployDemoExtraVaults
/// @notice Demo-only deploy script that registers two additional ERC-4626
///         vaults plus a non-Active RWA/Thematic placeholder in
///         `VaultRegistry` and re-sets the router weight vector to a
///         non-degenerate three-way split.
///
///         Why this exists: to exercise the multi-vault router story end to end
///         (Portfolio Explorer, /v1/vaults TVL, Router Governance weights) the
///         demo registers two extra `RobotMoneyVault` instances wired to
///         `PassthroughAdapter` — the same adapter the smoke-test devnet
///         already uses for the primary vault. They are demo-only stand-ins;
///         no mainnet build runs this script.
///
///         AgentTokenVault shortlist (docs/adr/ADR-0001-mvp-agent-token-shortlist.md,
///         accepted): the shortlist-side block is resolved — this script now
///         also deploys a real `AgentTokenVault` and seeds it with the
///         canonical MVP six-token shortlist (JUNO, ROBOTMONEY, BANKR, ZYFAI,
///         GIZA, DEUS, equal-weight) using devnet stand-in ERC20s + stub V3
///         pools, then registers it in `VaultRegistry` so the dapp Portfolio
///         Explorer surfaces it via `AgentTokenVault.shortlist()`.
///         AgentTokenVault stays PROTOTYPE-labeled and is NOT marked
///         router-eligible: that remains blocked independently by the
///         basket-vault gap report
///         (`docs/technical/basket-vault-gap-report.md` — TWAP hardening and
///         slippage-bounded `previewRedeem`). `ProtocolAssetVault` likewise
///         stays unseeded by this script for the same gap.
///
///         Four-vault PRD conformance (issue #479): PRD §11 names four vault
///         categories — Stable Yield, Protocol Asset, Agent Token, and
///         RWA/Thematic. PRD §11.4 marks RWA/Thematic as Future / not
///         specified. To make the deployed vault set match the four-vault
///         catalog, this script also registers a single RWA/Thematic
///         placeholder. It is registered then set to a non-Active status
///         (Paused) and is never marked router-eligible, so `PortfolioRouter`
///         skips it (it is not in the weight vector) and the dapp renders it
///         as a Future / Coming-soon tile whose inactive state is read from
///         on-chain status, not a hard-coded flag. This is registry state, not
///         a code variant — single-production-codebase
///         (`docs/development/single-production-codebase.md`).
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
///           WEIGHT_EXTRA1_BPS  — bps for the first extra vault
///           WEIGHT_EXTRA2_BPS  — bps for the second extra vault
///                                (the three must sum to 10 000)
///
///         Optional env vars:
///           VAULT1_NAME        — registry name for the first extra vault
///                                (default: "Robot Money Demo Vault A")
///           VAULT2_NAME        — registry name for the second extra vault
///                                (default: "Robot Money Demo Vault B")
///           RWA_VAULT_NAME     — registry name for the RWA/Thematic
///                                placeholder
///                                (default: "Robot Money RWA / Thematic")
///           DEPLOYMENT_OUT     — output JSON path
///                                (default: "deployments/demo-extra-vaults-<chain_id>.json")
contract DeployDemoExtraVaults is Script {
    using stdJson for string;

    /// @notice Result struct returned to in-process callers (e.g. forge tests).
    struct Deployed {
        address vault1;
        address vault2;
        address adapter1;
        address adapter2;
        uint256 weightPrimaryBps;
        uint256 weightExtra1Bps;
        uint256 weightExtra2Bps;
        /// @dev RWA/Thematic placeholder (issue #479). Registered non-Active
        ///      (Paused) and never router-eligible; not in the weight vector.
        address rwaVault;
        // AgentTokenVault seeded with the canonical MVP six-token shortlist
        // (ADR-0001). Registered in VaultRegistry but NOT router-eligible.
        address agentTokenVault;
        address[] agentTokens;
    }

    /// @notice Canonical MVP AgentTokenVault shortlist symbols, in deploy order
    ///         (docs/adr/ADR-0001-mvp-agent-token-shortlist.md). PEAQ excluded.
    string[6] internal AGENT_SYMBOLS = ["JUNO", "ROBOTMONEY", "BANKR", "ZYFAI", "GIZA", "DEUS"];
    /// @notice Default swap fee tier for demo stand-in pools (agent tokens are
    ///         illiquid; matches AgentTokenVault's 3% default-slippage stance).
    uint24 internal constant DEMO_AGENT_SWAP_FEE = 10_000;

    /// @notice Default human-readable name for the first extra demo vault.
    string public constant DEFAULT_VAULT1_NAME = "Robot Money Demo Vault A";
    /// @notice Default human-readable name for the second extra demo vault.
    string public constant DEFAULT_VAULT2_NAME = "Robot Money Demo Vault B";
    /// @notice Default human-readable name for the RWA/Thematic placeholder
    ///         (issue #479, PRD §11.4). Future / not-specified vault category.
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
        // Uniswap V3 SwapRouter02 for AgentTokenVault. On devnet no swaps run
        // during seed (only addAsset + register), so a non-functional address
        // is acceptable; defaults to the Base mainnet SwapRouter02.
        address swapRouter;
        uint256 wPrimary;
        uint256 wExtra1;
        uint256 wExtra2;
        string name1;
        string name2;
        string rwaName;
    }

    /// @notice Base mainnet Uniswap V3 SwapRouter02 — default AgentTokenVault
    ///         swap router when SWAP_ROUTER is unset (mirrors AgentTokenVault).
    address internal constant DEFAULT_SWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;

    /// @notice Forge broadcast entrypoint. Deploys two extra demo vaults +
    ///         passthrough adapters, registers them, attests them on the
    ///         router, and resets the router weight vector.
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
    ///         is written. Used by `test_demo_seed_populates_defaultWeights`.
    /// @param p Fully-formed params (no env reads).
    function runInProcess(Params memory p) external returns (Deployed memory d) {
        require(p.wPrimary + p.wExtra1 + p.wExtra2 == 10_000, "weights must sum to 10000");
        require(p.wPrimary > 0 && p.wExtra1 > 0 && p.wExtra2 > 0, "weights must be non-zero");
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
        p.wExtra1 = vm.envUint("WEIGHT_EXTRA1_BPS");
        p.wExtra2 = vm.envUint("WEIGHT_EXTRA2_BPS");
        p.name1 = _envStringOrDefault("VAULT1_NAME", DEFAULT_VAULT1_NAME);
        p.name2 = _envStringOrDefault("VAULT2_NAME", DEFAULT_VAULT2_NAME);
        p.rwaName = _envStringOrDefault("RWA_VAULT_NAME", DEFAULT_RWA_NAME);

        require(p.admin != address(0), "ADMIN_ADDRESS=0");
        require(p.registry != address(0), "REGISTRY_ADDRESS=0");
        require(p.router != address(0), "ROUTER_ADDRESS=0");
        require(p.primaryVault != address(0), "PRIMARY_VAULT=0");
        require(p.usdc != address(0), "USDC_ADDRESS=0");
        require(p.wPrimary + p.wExtra1 + p.wExtra2 == 10_000, "weights must sum to 10000");
        require(p.wPrimary > 0 && p.wExtra1 > 0 && p.wExtra2 > 0, "weights must be non-zero");
    }

    /// @dev Caller must hold ADMIN_ROLE on registry + router via broadcast
    ///      key. Splits the body of `run()` so the locals stay below the
    ///      stack-too-deep limit.
    function _doDeploy(Params memory p) internal returns (Deployed memory d) {
        // 1. Single batched CREATE: all RobotMoneyVault, PassthroughAdapter,
        //    AgentTokenVault, and AgentBasketStubDeployer instances are built
        //    inside one `DemoVaultBatchDeployer` constructor. The vaults are
        //    constructed with admin = p.admin (the broadcaster), so subsequent
        //    addAdapter/addAsset/registry calls — still issued from the script
        //    broadcaster — continue to work. This collapses what was 7
        //    broadcaster CREATEs (3 vaults + 2 adapters + 1 AgentTokenVault + 1
        //    basket stub batcher) down to 1, saving ~78s on the smoke-test
        //    chain-boot so the dapp-e2e globalSetup budget can absorb a cold
        //    dapp Docker build.
        DemoVaultBatchDeployer batch = new DemoVaultBatchDeployer(
            p.usdc, p.admin, p.swapRouter, DEMO_TVL_CAP, DEMO_PER_DEPOSIT_CAP, AGENT_SYMBOLS
        );

        // Stash the batch-deployed addresses in the result struct immediately
        // so we don't have to keep all seven contract handles live as locals
        // (avoids stack-too-deep across the wiring + registry + weights calls).
        d.vault1 = address(batch.vault1());
        d.vault2 = address(batch.vault2());
        d.adapter1 = address(batch.adapter1());
        d.adapter2 = address(batch.adapter2());
        d.rwaVault = address(batch.rwaVault());
        d.agentTokenVault = address(batch.agentVault());
        d.weightPrimaryBps = p.wPrimary;
        d.weightExtra1Bps = p.wExtra1;
        d.weightExtra2Bps = p.wExtra2;

        // 2. Approve + wire each adapter on its vault. PassthroughAdapter is the
        //    same path the primary vault uses on devnet
        //    (USE_PASSTHROUGH_ADAPTER=true in Deploy.s.sol), so deposit flow is
        //    identical and no fork-state assumptions are introduced.
        _wireAdapterOn(RobotMoneyVault(d.vault1), PassthroughAdapter(d.adapter1));
        _wireAdapterOn(RobotMoneyVault(d.vault2), PassthroughAdapter(d.adapter2));

        // 3. Register both extra vaults in the registry (idempotent).
        VaultRegistry registry = VaultRegistry(p.registry);
        _registerIfAbsent(registry, d.vault1, p.usdc, p.name1);
        _registerIfAbsent(registry, d.vault2, p.usdc, p.name2);

        // 4. Mark both extra vaults router-eligible in the registry so
        //    setWeights accepts them. The primary vault is already opted in by
        //    DeployPortfolioRouter.s.sol (see issue #475 — single registry
        //    eligibility gate; same contracts every environment).
        registry.setRouterEligible(d.vault1, true);
        registry.setRouterEligible(d.vault2, true);

        // 5/6. Reset the router voted weight vector AND the on-chain default
        //      (below-quorum fallback) vector to the three-way split. Default
        //      vector length must match the registry's router-eligible count,
        //      so link the router on the registry first (idempotent).
        if (address(registry.router()) != p.router) {
            registry.setRouter(p.router);
        }
        _applyThreeWayWeights(PortfolioRouter(p.router), p.primaryVault, d.vault1, d.vault2, p);

        // 7. Register the RWA/Thematic placeholder (issue #479). It rounds the
        //    deployed set out to the four PRD §11 categories. Registered then
        //    immediately set to non-Active (Paused) and never router-eligible
        //    (registry default). PortfolioRouter never weights or deposits into
        //    it (not in the weight vector, isRouterEligible() == false); the
        //    dapp renders it as a Future / Coming-soon tile from on-chain
        //    status, not a hard-coded flag. No adapter is wired: the
        //    placeholder takes no deposits.
        registry.registerVault(
            d.rwaVault,
            VaultRegistry.VaultMetadata({name: p.rwaName, asset: p.usdc, registeredAt: 0})
        );
        registry.setVaultStatus(d.rwaVault, VaultRegistry.VaultStatus.Paused);

        // 8. Seed AgentTokenVault with the canonical MVP six-token shortlist
        //    (ADR-0001). Registered for display, NOT router-eligible — the
        //    basket-vault gap (TWAP, previewRedeem) blocks that independently.
        d.agentTokens = _seedAgentTokenVault(
            p, registry, AgentTokenVault(d.agentTokenVault), batch.basketStubs()
        );
    }

    /// @dev Approve and wire `adapter_` on `vault_`. The vault was constructed
    ///      with admin = broadcaster inside `DemoVaultBatchDeployer`, so these
    ///      ADMIN_ROLE-guarded calls succeed from the script broadcast key.
    function _wireAdapterOn(RobotMoneyVault vault_, PassthroughAdapter adapter_) internal {
        _approveAdapter(vault_, address(adapter_));
        vault_.addAdapter(address(adapter_), 10_000);
    }

    /// @dev Set both the voted weight vector (used by AC3 smoke test which
    ///      reads `getWeights()`) and the on-chain default (below-quorum
    ///      fallback, ADR-0002) to the same three-way split. Bundled into one
    ///      helper to keep the `_doDeploy` stack below the solc limit.
    function _applyThreeWayWeights(
        PortfolioRouter router,
        address primary,
        address extra1,
        address extra2,
        Params memory p
    ) internal {
        _setThreeWayWeights(router, primary, extra1, extra2, p);
        _setThreeWayDefaultWeights(router, primary, extra1, extra2, p);
    }

    /// @dev Wire the six MVP shortlist tokens into the pre-built
    ///      `AgentTokenVault` via `addAsset` (still a broadcaster tx; the
    ///      vault's ADMIN_ROLE is held by p.admin). The tokens themselves and
    ///      the matching USDC stub pools were already created inside the
    ///      single batched `DemoVaultBatchDeployer` CREATE. The vault is
    ///      intentionally left router-ineligible — basket-vault gap (TWAP,
    ///      previewRedeem) blocks that independently of the now-resolved
    ///      shortlist question.
    function _seedAgentTokenVault(
        Params memory p,
        VaultRegistry registry,
        AgentTokenVault vault,
        AgentBasketStubDeployer seeder
    ) internal returns (address[] memory tokens) {
        tokens = new address[](AGENT_SYMBOLS.length);
        for (uint256 i = 0; i < AGENT_SYMBOLS.length; i++) {
            address token_ = address(seeder.tokens(i));
            address pool_ = address(seeder.pools(i));
            vault.addAsset(token_, pool_, DEMO_AGENT_SWAP_FEE);
            tokens[i] = token_;
        }

        _registerIfAbsent(registry, address(vault), p.usdc, "Robot Money Agent Tokens");
        // Deliberately NOT calling registry.setRouterEligible(vault, true):
        // AgentTokenVault remains router-ineligible until the basket-vault gap
        // closes (docs/technical/basket-vault-gap-report.md).
    }

    function _setThreeWayWeights(
        PortfolioRouter router,
        address primary,
        address extra1,
        address extra2,
        Params memory p
    ) internal {
        address[] memory vaults = new address[](3);
        vaults[0] = primary;
        vaults[1] = extra1;
        vaults[2] = extra2;
        uint256[] memory bps = new uint256[](3);
        bps[0] = p.wPrimary;
        bps[1] = p.wExtra1;
        bps[2] = p.wExtra2;
        router.setWeights(vaults, bps);
    }

    /// @dev Populate the router's default (below-quorum fallback) weight vector
    ///      with the same three-way split. ADR-0002: this is the vector the
    ///      router routes by — and the allocation surface renders — with no
    ///      governance activity.
    function _setThreeWayDefaultWeights(
        PortfolioRouter router,
        address primary,
        address extra1,
        address extra2,
        Params memory p
    ) internal {
        address[] memory vaults = new address[](3);
        vaults[0] = primary;
        vaults[1] = extra1;
        vaults[2] = extra2;
        uint256[] memory bps = new uint256[](3);
        bps[0] = p.wPrimary;
        bps[1] = p.wExtra1;
        bps[2] = p.wExtra2;
        router.setDefaultWeights(vaults, bps);
    }

    // ─── Internal ────────────────────────────────────────────────────────────

    /// @dev Approve `adapter_` on `vault_` matching Deploy.s.sol semantics:
    ///      assert no DELEGATECALL in adapter runtime, then allowlist address
    ///      and codehash.
    function _approveAdapter(RobotMoneyVault vault_, address adapter_) internal {
        AdapterBytecodeGuard.requireNoDelegatecall(adapter_);
        vault_.setAdapterAllowed(adapter_, true);
        vault_.setAdapterCodeHashAllowed(adapter_.codehash, true);
    }

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
        console2.log("  vault1     :", d.vault1);
        console2.log("  vault2     :", d.vault2);
        console2.log("  rwaVault   :", d.rwaVault);
        console2.log("  agentVault :", d.agentTokenVault);
        console2.log("  agentTokens:", d.agentTokens.length);
        console2.log("  wPrimary   :", d.weightPrimaryBps);
        console2.log("  wExtra1    :", d.weightExtra1Bps);
        console2.log("  wExtra2    :", d.weightExtra2Bps);
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
        vm.serializeAddress(obj, "vault1", d.vault1);
        vm.serializeAddress(obj, "vault2", d.vault2);
        vm.serializeAddress(obj, "adapter1", d.adapter1);
        vm.serializeAddress(obj, "adapter2", d.adapter2);
        vm.serializeAddress(obj, "rwa_vault", d.rwaVault);
        vm.serializeAddress(obj, "agent_token_vault", d.agentTokenVault);
        vm.serializeAddress(obj, "agent_tokens", d.agentTokens);
        vm.serializeUint(obj, "weight_primary_bps", d.weightPrimaryBps);
        vm.serializeUint(obj, "weight_extra1_bps", d.weightExtra1Bps);
        string memory json = vm.serializeUint(obj, "weight_extra2_bps", d.weightExtra2Bps);

        vm.writeJson(json, outPath);
        console2.log("Wrote demo extra vaults deployment JSON to", outPath);
    }
}
