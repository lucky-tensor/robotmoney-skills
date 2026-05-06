//! `rmpc` — Robot Money payment client CLI entry point.
//!
//! All command logic lives in [`rust_payment_client::commands`]; this file
//! is a thin shim that parses argv and dispatches.

use clap::Parser;
use rust_payment_client::cli::{Cli, Command};
use rust_payment_client::commands;

fn main() {
    let cli = Cli::parse();
    let exit_code = match cli.command {
        Command::Deposit {
            config,
            amount,
            order_id,
            idempotency_key,
            deadline_secs,
            receipt_timeout_secs,
            gas_limit,
            pretty,
        } => commands::deposit::run(commands::deposit::Args {
            config_path: config,
            amount,
            order_id,
            idempotency_key,
            deadline_secs,
            receipt_timeout_secs,
            gas_limit,
            pretty,
        }),
        Command::SelfCheck { config, pretty } => commands::self_check::run(&config, pretty),
        Command::Status {
            config,
            payment_id,
            pretty,
        } => commands::status::run(&config, &payment_id, pretty),
    };
    std::process::exit(exit_code);
}
