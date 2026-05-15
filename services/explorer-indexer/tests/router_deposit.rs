//! Suite-09 — AgentDepositRouted and RouterDeposit event indexing (issue #373).
//!
//! Acceptance criteria exercised here:
//!
//! AC-1: Indexer decodes AgentDepositRouted and stores a parent row in
//!       agent_deposits with vault = NULL; per-leg shares summed into
//!       shares_minted.
//!
//! AC-2: Indexer decodes RouterDeposit and stores one row per leg in
//!       router_deposit_legs with the correct vault address and amount.
//!
//! All tests skip cleanly when Docker is not available.
//!
//! Canonical: docs/implementation-plan.md §"Phase: Multi-vault explorer"
//!            services/explorer-indexer/migrations/0006_agent_deposit_vault_and_router_legs.sql

mod common;

use alloy_primitives::{Address, U256};
use alloy_sol_types::SolEvent as _;
use common::{try_pg_fixture, StubRpcServer};
use explorer_indexer::{
    abi::{IGatewayEvents, IPortfolioRouterEvents},
    db::CountTable,
    indexer::{run_once, IndexerConfig},
    rpc::JsonRpc,
};

// ── Helpers ──────────────────────────────────────────────────────────────────

fn stub_block(number: u64, hash_byte: u8, parent_byte: u8) -> serde_json::Value {
    serde_json::json!({
        "number":     format!("0x{:x}", number),
        "hash":       format!("0x{}", hex::encode([hash_byte; 32])),
        "parentHash": format!("0x{}", hex::encode([parent_byte; 32])),
        "timestamp":  "0x65000000",
        "transactions": []
    })
}

/// Encode an `AgentDepositRouted` log from IGateway.
///
/// IGateway.sol:119 — emitted for multi-leg router deposits:
/// `AgentDepositRouted(bytes32 indexed paymentId, bytes32 indexed orderId,
///                     address indexed agent, address shareReceiver, address router,
///                     uint256 amount, uint256[] sharesPerLeg, uint64 windowId)`
#[allow(clippy::too_many_arguments)]
fn encode_agent_deposit_routed_log(
    gateway_addr: Address,
    payment_id: [u8; 32],
    order_id: [u8; 32],
    agent: Address,
    share_receiver: Address,
    router: Address,
    amount: U256,
    shares_per_leg: Vec<U256>,
    window_id: u64,
    block_number: u64,
    tx_hash: [u8; 32],
    log_index: u32,
) -> serde_json::Value {
    use alloy_primitives::{FixedBytes, LogData};

    let event = IGatewayEvents::AgentDepositRouted {
        paymentId: FixedBytes::from(payment_id),
        orderId: FixedBytes::from(order_id),
        agent,
        shareReceiver: share_receiver,
        router,
        amount,
        sharesPerLeg: shares_per_leg,
        windowId: window_id,
    };
    let log_data: LogData = event.encode_log_data();
    let topics: Vec<String> = log_data
        .topics()
        .iter()
        .map(|t| format!("{:#x}", t))
        .collect();
    let data_hex = format!("0x{}", hex::encode(log_data.data.as_ref()));

    serde_json::json!({
        "address":          format!("{:#x}", gateway_addr),
        "topics":           topics,
        "data":             data_hex,
        "blockNumber":      format!("0x{:x}", block_number),
        "blockHash":        format!("0x{}", hex::encode([0xabu8; 32])),
        "transactionHash":  format!("0x{}", hex::encode(tx_hash)),
        "transactionIndex": "0x0",
        "logIndex":         format!("0x{:x}", log_index),
    })
}

/// Encode a `RouterDeposit` log from PortfolioRouter.
///
/// PortfolioRouter.sol:71 — emitted once per vault leg:
/// `RouterDeposit(address indexed depositor, address indexed vault,
///                uint256 amount, uint256 shares, uint256 weightBps)`
#[allow(clippy::too_many_arguments)]
fn encode_router_deposit_log(
    router_addr: Address,
    depositor: Address,
    vault: Address,
    amount: U256,
    shares: U256,
    weight_bps: U256,
    block_number: u64,
    tx_hash: [u8; 32],
    log_index: u32,
) -> serde_json::Value {
    use alloy_primitives::LogData;

    let event = IPortfolioRouterEvents::RouterDeposit {
        depositor,
        vault,
        amount,
        shares,
        weightBps: weight_bps,
    };
    let log_data: LogData = event.encode_log_data();
    let topics: Vec<String> = log_data
        .topics()
        .iter()
        .map(|t| format!("{:#x}", t))
        .collect();
    let data_hex = format!("0x{}", hex::encode(log_data.data.as_ref()));

    serde_json::json!({
        "address":          format!("{:#x}", router_addr),
        "topics":           topics,
        "data":             data_hex,
        "blockNumber":      format!("0x{:x}", block_number),
        "blockHash":        format!("0x{}", hex::encode([0xbcu8; 32])),
        "transactionHash":  format!("0x{}", hex::encode(tx_hash)),
        "transactionIndex": "0x0",
        "logIndex":         format!("0x{:x}", log_index),
    })
}

// ── Tests ─────────────────────────────────────────────────────────────────────

/// AC-1: AgentDepositRouted stores a parent agent_deposits row with vault = NULL.
///
/// Emitting one AgentDepositRouted with two legs (sharesPerLeg = [300, 200])
/// must produce exactly one agent_deposits row whose:
///   - vault column IS NULL (router path — per-leg data goes in router_deposit_legs)
///   - shares_minted = sum(sharesPerLeg) = 500
#[tokio::test]
async fn agent_deposit_routed_stored_with_null_vault_and_summed_shares() {
    let Some(fx) = try_pg_fixture().await else {
        return;
    };

    let gateway_addr = Address::from([0x11u8; 20]);
    let agent = Address::from([0xAAu8; 20]);
    let share_receiver = Address::from([0xBBu8; 20]);
    let router_addr = Address::from([0xCCu8; 20]);
    let vault_a = Address::from([0xDDu8; 20]);

    let payment_id = [0x11u8; 32];
    let order_id = [0x22u8; 32];
    let tx_hash = [0x33u8; 32];

    let amount = U256::from(1_000_000u64);
    let shares_a = U256::from(300u64);
    let shares_b = U256::from(200u64);

    let routed_log = encode_agent_deposit_routed_log(
        gateway_addr,
        payment_id,
        order_id,
        agent,
        share_receiver,
        router_addr,
        amount,
        vec![shares_a, shares_b],
        1u64, // windowId
        50u64,
        tx_hash,
        0u32,
    );

    let stub = StubRpcServer::start().await;
    stub.set(
        "eth_blockNumber",
        serde_json::Value::String("0x46".into()), // 70
    );
    stub.set("eth_getLogs", serde_json::Value::Array(vec![routed_log]));
    stub.set(
        "eth_call",
        serde_json::Value::String(format!("0x{}", "00".repeat(32))),
    );
    stub.set("eth_getBlockByNumber", stub_block(65, 0xab, 0xaa));

    let rpc = JsonRpc::new(&stub.url);
    let cfg = IndexerConfig {
        chain_id: 8453,
        chain_name: "base".into(),
        rpc_label: "stub".into(),
        gateway: gateway_addr,
        vault: vault_a,
        registry: None,
        router_governance: None,
        max_blocks_per_tick: 200,
        end_block: Some(65),
    };

    let o = run_once(&fx.db, &rpc, &cfg).await.unwrap();
    assert!(o.error.is_none(), "tick must succeed: {:?}", o.error);
    stub.shutdown();

    // Exactly one agent_deposits row must exist.
    let dep_count = fx.db.count(CountTable::AgentDeposits).await.unwrap();
    assert_eq!(
        dep_count, 1,
        "AgentDepositRouted must produce exactly one agent_deposits row"
    );

    // vault column must be NULL (router path).
    let row: (Option<Vec<u8>>, bigdecimal::BigDecimal) =
        sqlx::query_as("SELECT vault, shares_minted FROM agent_deposits WHERE chain_id = $1")
            .bind(8453i64)
            .fetch_one(fx.db.pool())
            .await
            .unwrap();
    let (vault_bytes, shares_minted) = row;
    assert!(
        vault_bytes.is_none(),
        "AgentDepositRouted must store vault = NULL (router path)"
    );
    // shares_minted must equal sum(sharesPerLeg) = 300 + 200 = 500.
    assert_eq!(
        shares_minted.to_string(),
        "500",
        "shares_minted must equal sum of sharesPerLeg (300 + 200 = 500)"
    );
}

/// AC-2: RouterDeposit stores one row per leg in router_deposit_legs.
///
/// Emitting two RouterDeposit events (vault A and vault B) must produce
/// exactly two router_deposit_legs rows with correct vault addresses,
/// amounts, and weight_bps values.
#[tokio::test]
async fn router_deposit_stores_per_leg_rows_with_correct_vault_and_amount() {
    let Some(fx) = try_pg_fixture().await else {
        return;
    };

    let gateway_addr = Address::from([0x11u8; 20]);
    let router_addr = Address::from([0xCCu8; 20]);
    let vault_a = Address::from([0xAAu8; 20]);
    let vault_b = Address::from([0xBBu8; 20]);
    let depositor = Address::from([0xDDu8; 20]);

    let tx_hash = [0x44u8; 32];

    // Two RouterDeposit legs at block 50.
    let leg_a = encode_router_deposit_log(
        router_addr,
        depositor,
        vault_a,
        U256::from(600_000u64), // amount to vault A
        U256::from(600u64),     // shares minted
        U256::from(6000u64),    // 60% weight
        50u64,
        tx_hash,
        0u32,
    );
    let leg_b = encode_router_deposit_log(
        router_addr,
        depositor,
        vault_b,
        U256::from(400_000u64), // amount to vault B
        U256::from(400u64),     // shares minted
        U256::from(4000u64),    // 40% weight
        50u64,
        tx_hash,
        1u32,
    );

    let stub = StubRpcServer::start().await;
    stub.set(
        "eth_blockNumber",
        serde_json::Value::String("0x46".into()), // 70
    );
    stub.set("eth_getLogs", serde_json::Value::Array(vec![leg_a, leg_b]));
    stub.set(
        "eth_call",
        serde_json::Value::String(format!("0x{}", "00".repeat(32))),
    );
    stub.set("eth_getBlockByNumber", stub_block(65, 0xab, 0xaa));

    let rpc = JsonRpc::new(&stub.url);
    let cfg = IndexerConfig {
        chain_id: 8453,
        chain_name: "base".into(),
        rpc_label: "stub".into(),
        gateway: gateway_addr,
        vault: vault_a,
        registry: None,
        router_governance: None,
        max_blocks_per_tick: 200,
        end_block: Some(65),
    };

    let o = run_once(&fx.db, &rpc, &cfg).await.unwrap();
    assert!(o.error.is_none(), "tick must succeed: {:?}", o.error);
    stub.shutdown();

    // Two router_deposit_legs rows must exist.
    let leg_count = fx.db.count(CountTable::RouterDepositLegs).await.unwrap();
    assert_eq!(
        leg_count, 2,
        "two RouterDeposit events must produce 2 router_deposit_legs rows"
    );

    // Leg for vault_a: amount=600000, weight_bps=6000.
    let row_a: (Vec<u8>, bigdecimal::BigDecimal, bigdecimal::BigDecimal) = sqlx::query_as(
        "SELECT vault, amount, weight_bps FROM router_deposit_legs \
         WHERE chain_id = $1 AND log_index = 0",
    )
    .bind(8453i64)
    .fetch_one(fx.db.pool())
    .await
    .unwrap();
    assert_eq!(row_a.0, vault_a.as_slice(), "leg 0 must point to vault_a");
    assert_eq!(row_a.1.to_string(), "600000", "leg 0 amount must be 600000");
    assert_eq!(row_a.2.to_string(), "6000", "leg 0 weight_bps must be 6000");

    // Leg for vault_b: amount=400000, weight_bps=4000.
    let row_b: (Vec<u8>, bigdecimal::BigDecimal, bigdecimal::BigDecimal) = sqlx::query_as(
        "SELECT vault, amount, weight_bps FROM router_deposit_legs \
         WHERE chain_id = $1 AND log_index = 1",
    )
    .bind(8453i64)
    .fetch_one(fx.db.pool())
    .await
    .unwrap();
    assert_eq!(row_b.0, vault_b.as_slice(), "leg 1 must point to vault_b");
    assert_eq!(row_b.1.to_string(), "400000", "leg 1 amount must be 400000");
    assert_eq!(row_b.2.to_string(), "4000", "leg 1 weight_bps must be 4000");
}

/// AC-1+AC-2 combined: AgentDepositRouted + RouterDeposit in the same block.
///
/// A realistic deposit scenario: one AgentDepositRouted parent event followed
/// by two RouterDeposit leg events in the same transaction.  The parent row
/// must carry vault=NULL and legs must be linked by tx_hash (payment_id).
#[tokio::test]
async fn routed_deposit_parent_and_legs_stored_in_same_tick() {
    let Some(fx) = try_pg_fixture().await else {
        return;
    };

    let gateway_addr = Address::from([0x11u8; 20]);
    let router_addr = Address::from([0xCCu8; 20]);
    let vault_a = Address::from([0xAAu8; 20]);
    let vault_b = Address::from([0xBBu8; 20]);
    let agent = Address::from([0xEEu8; 20]);
    let share_receiver = Address::from([0xFFu8; 20]);

    let payment_id = [0x55u8; 32];
    let order_id = [0x66u8; 32];
    let tx_hash = [0x77u8; 32];

    let total_amount = U256::from(1_000_000u64);
    let shares_a = U256::from(700u64);
    let shares_b = U256::from(300u64);

    let routed_parent = encode_agent_deposit_routed_log(
        gateway_addr,
        payment_id,
        order_id,
        agent,
        share_receiver,
        router_addr,
        total_amount,
        vec![shares_a, shares_b],
        1u64,
        50u64,
        tx_hash,
        0u32,
    );
    let leg_a = encode_router_deposit_log(
        router_addr,
        agent,
        vault_a,
        U256::from(700_000u64),
        shares_a,
        U256::from(7000u64),
        50u64,
        tx_hash,
        1u32,
    );
    let leg_b = encode_router_deposit_log(
        router_addr,
        agent,
        vault_b,
        U256::from(300_000u64),
        shares_b,
        U256::from(3000u64),
        50u64,
        tx_hash,
        2u32,
    );

    let stub = StubRpcServer::start().await;
    stub.set(
        "eth_blockNumber",
        serde_json::Value::String("0x46".into()), // 70
    );
    stub.set(
        "eth_getLogs",
        serde_json::Value::Array(vec![routed_parent, leg_a, leg_b]),
    );
    stub.set(
        "eth_call",
        serde_json::Value::String(format!("0x{}", "00".repeat(32))),
    );
    stub.set("eth_getBlockByNumber", stub_block(65, 0xab, 0xaa));

    let rpc = JsonRpc::new(&stub.url);
    let cfg = IndexerConfig {
        chain_id: 8453,
        chain_name: "base".into(),
        rpc_label: "stub".into(),
        gateway: gateway_addr,
        vault: vault_a,
        registry: None,
        router_governance: None,
        max_blocks_per_tick: 200,
        end_block: Some(65),
    };

    let o = run_once(&fx.db, &rpc, &cfg).await.unwrap();
    assert!(o.error.is_none(), "tick must succeed: {:?}", o.error);
    stub.shutdown();

    // One parent deposit row.
    let dep_count = fx.db.count(CountTable::AgentDeposits).await.unwrap();
    assert_eq!(dep_count, 1, "one parent agent_deposits row expected");

    // Two leg rows.
    let leg_count = fx.db.count(CountTable::RouterDepositLegs).await.unwrap();
    assert_eq!(leg_count, 2, "two router_deposit_legs rows expected");

    // Parent row: vault = NULL, shares_minted = 1000 (700 + 300).
    let parent: (Option<Vec<u8>>, bigdecimal::BigDecimal) =
        sqlx::query_as("SELECT vault, shares_minted FROM agent_deposits WHERE chain_id = $1")
            .bind(8453i64)
            .fetch_one(fx.db.pool())
            .await
            .unwrap();
    assert!(parent.0.is_none(), "parent row must have vault = NULL");
    assert_eq!(
        parent.1.to_string(),
        "1000",
        "shares_minted must be sum of sharesPerLeg (700 + 300 = 1000)"
    );

    // Leg rows must link to the parent via tx_hash (correlation key).
    let legs: Vec<(Vec<u8>, Vec<u8>)> = sqlx::query_as(
        "SELECT vault, payment_id FROM router_deposit_legs WHERE chain_id = $1 ORDER BY log_index",
    )
    .bind(8453i64)
    .fetch_all(fx.db.pool())
    .await
    .unwrap();
    assert_eq!(legs[0].0, vault_a.as_slice(), "leg 0 vault must be vault_a");
    assert_eq!(legs[1].0, vault_b.as_slice(), "leg 1 vault must be vault_b");
    // payment_id on legs = tx_hash (best-effort correlation key).
    assert_eq!(
        legs[0].1, tx_hash,
        "leg payment_id must equal tx_hash (correlation key)"
    );
}
