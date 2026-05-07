//! Canonical: docs/walkthroughs/opencode-readonly-fork.md (issue #53),
//! steps 5–6 (read-only inspection + get-gateway degradation shape).
//! Fixes: issue #107.
//!
//! Two tests:
//!
//! - `get_vault_against_fork_envelope_contract` — boots anvil pinned to
//!   `RMPC_FORK_BLOCK`, runs `rmpc get-vault`, asserts the §9 envelope
//!   contract **and** vault data fields (`asset`, `symbol`, `decimals`).
//!
//! - `get_gateway_against_fork_is_partial` — same fork, runs
//!   `rmpc get-gateway` with the dead EOA gateway address the walkthrough
//!   fixture ships. Asserts `partial: true` + non-empty named per-field
//!   errors — the documented degradation shape, not a bug.
//!
//! Both skip-clean when `RMPC_FORK_RPC_URL` is unset, mirroring
//! `testing/fork-e2e-rust`. The fork is pinned to `RMPC_FORK_BLOCK`
//! (set in the workflow `env:` block per fork-e2e ADR §3.2); when unset
//! locally, anvil forks at latest.

use std::fs;
use std::io::Read;
use std::net::TcpStream;
use std::process::{Child, Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

use opencode_walkthrough_tests::{config_template_path, rmpc_bin};
use serde_json::Value;

/// Base mainnet USDC — the asset the Robot Money vault holds.
const BASE_USDC: &str = "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913";

macro_rules! skip_if_no_fork {
    () => {
        match std::env::var("RMPC_FORK_RPC_URL") {
            Ok(s) if !s.is_empty() => s,
            _ => {
                eprintln!(
                    "[opencode-walkthrough] skipping: RMPC_FORK_RPC_URL not set. \
                     Configure an archive RPC to exercise the fork tests."
                );
                return;
            }
        }
    };
}

fn pick_port() -> u16 {
    let listener = std::net::TcpListener::bind("127.0.0.1:0").expect("bind ephemeral port");
    let port = listener.local_addr().unwrap().port();
    drop(listener);
    port
}

struct AnvilGuard {
    child: Child,
    port: u16,
}

impl Drop for AnvilGuard {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn boot_anvil(fork_url: &str) -> Result<AnvilGuard, String> {
    if which::which("anvil").is_err() {
        return Err("anvil not on PATH (install Foundry)".into());
    }
    let port = pick_port();
    let mut cmd = Command::new("anvil");
    cmd.args([
        "--fork-url",
        fork_url,
        "--port",
        &port.to_string(),
        "--silent",
    ]);
    // Pin the fork block when provided (fork-e2e ADR §3.2).
    if let Ok(block) = std::env::var("RMPC_FORK_BLOCK") {
        if !block.is_empty() {
            cmd.args(["--fork-block-number", &block]);
        }
    }
    cmd.stdout(Stdio::null()).stderr(Stdio::piped());
    let child = cmd.spawn().map_err(|e| format!("spawn anvil: {e}"))?;

    let deadline = Instant::now() + Duration::from_secs(30);
    while Instant::now() < deadline {
        if TcpStream::connect_timeout(
            &format!("127.0.0.1:{port}").parse().unwrap(),
            Duration::from_millis(200),
        )
        .is_ok()
        {
            return Ok(AnvilGuard { child, port });
        }
        thread::sleep(Duration::from_millis(200));
    }
    Err("anvil did not become reachable within 30s".into())
}

fn write_temp_config(tmp: &tempfile::TempDir, port: u16) -> std::path::PathBuf {
    let template = fs::read_to_string(config_template_path()).expect("read template");
    let body = template.replace(
        "rpc_url               = \"http://127.0.0.1:8545\"",
        &format!("rpc_url               = \"http://127.0.0.1:{port}\""),
    );
    let path = tmp.path().join("rmpc-walkthrough.toml");
    fs::write(&path, body).expect("write temp config");
    path
}

/// Run `rmpc <args> --config <cfg>`, assert exit 0, parse stdout as JSON.
fn run_rmpc(cfg: &std::path::Path, subcmd: &str, extra: &[&str]) -> (Value, String) {
    let mut child = Command::new(rmpc_bin())
        .arg(subcmd)
        .args(["--config", cfg.to_str().unwrap()])
        .args(extra)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap_or_else(|e| panic!("spawn rmpc {subcmd}: {e}"));
    let mut stdout_buf = String::new();
    child
        .stdout
        .take()
        .unwrap()
        .read_to_string(&mut stdout_buf)
        .expect("read rmpc stdout");
    let status = child.wait().expect("wait rmpc");
    let mut stderr_buf = String::new();
    if let Some(mut e) = child.stderr.take() {
        let _ = e.read_to_string(&mut stderr_buf);
    }
    assert!(
        status.success(),
        "rmpc {subcmd} failed (exit {:?});\nstderr:\n{stderr_buf}\nstdout:\n{stdout_buf}",
        status.code()
    );
    let v: Value = serde_json::from_str(&stdout_buf).unwrap_or_else(|e| {
        panic!("rmpc {subcmd} stdout is not valid JSON: {e}\nstdout:\n{stdout_buf}")
    });
    (v, stderr_buf)
}

#[test]
fn get_vault_against_fork_envelope_contract() {
    let fork_url = skip_if_no_fork!();
    let anvil = match boot_anvil(&fork_url) {
        Ok(g) => g,
        Err(e) => {
            eprintln!("[opencode-walkthrough] skipping: {e}");
            return;
        }
    };
    let tmp = tempfile::tempdir().expect("tempdir");
    let cfg = write_temp_config(&tmp, anvil.port);

    let (v, _) = run_rmpc(&cfg, "get-vault", &[]);

    // Envelope contract (docs/technical/rmpc-read-output-contract.md).
    assert!(
        v.get("chain_id").is_some(),
        "envelope missing chain_id: {v}"
    );
    assert!(
        v.get("block_number").is_some(),
        "envelope missing block_number: {v}"
    );
    assert_eq!(
        v.get("source").and_then(Value::as_str),
        Some("json_rpc"),
        "envelope source must be json_rpc: {v}"
    );
    assert!(v.get("partial").is_some(), "envelope missing partial: {v}");
    assert!(
        v.get("errors").and_then(Value::as_array).is_some(),
        "envelope missing errors array: {v}"
    );

    // Vault data fields — confirms the fixture config points at the
    // real Robot Money vault on Base mainnet.
    let data = &v["data"];
    assert_eq!(
        data["asset"].as_str().unwrap_or("").to_lowercase(),
        BASE_USDC,
        "get-vault data.asset must be Base USDC"
    );
    assert_eq!(data["symbol"], "rmUSDC", "get-vault data.symbol drift");
    assert_eq!(data["decimals"], 6, "get-vault data.decimals must be 6");

    drop(anvil);
}

#[test]
fn get_gateway_against_fork_is_partial() {
    // Walkthrough step 5: "get-gateway returns partial: true with per-field
    // error entries because the configured gateway_address is an EOA on
    // Base — the documented degradation shape, not a bug."
    let fork_url = skip_if_no_fork!();
    let anvil = match boot_anvil(&fork_url) {
        Ok(g) => g,
        Err(e) => {
            eprintln!("[opencode-walkthrough] skipping: {e}");
            return;
        }
    };
    let tmp = tempfile::tempdir().expect("tempdir");
    let cfg = write_temp_config(&tmp, anvil.port);

    let (v, _) = run_rmpc(&cfg, "get-gateway", &[]);

    // Envelope contract.
    assert!(
        v.get("chain_id").is_some(),
        "envelope missing chain_id: {v}"
    );
    assert_eq!(
        v.get("source").and_then(Value::as_str),
        Some("json_rpc"),
        "envelope source must be json_rpc: {v}"
    );

    // Documented degradation shape — gateway_address in the fixture is
    // 0x000…dEaD (an EOA on Base), so every eth_call returns 0x and rmpc
    // records each sub-read as a named per-field error.
    assert_eq!(
        v["partial"], true,
        "get-gateway must be partial=true when gateway is not deployed: {v}"
    );
    let errors = v["errors"]
        .as_array()
        .expect("errors must be an array when partial=true");
    assert!(
        !errors.is_empty(),
        "get-gateway must report at least one named per-field error: {v}"
    );
    for e in errors {
        assert!(
            e["field"].is_string(),
            "each error entry must carry a `field` string: {e}"
        );
        assert!(
            e["error"].is_string(),
            "each error entry must carry an `error` string: {e}"
        );
    }

    drop(anvil);
}
