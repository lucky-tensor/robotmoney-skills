# Minimal multi-stage build for the explorer-indexer binary.
#
# Canonical: docs/implementation-plan.md §11 — Phase 5.
# Used by: docker-compose.full-stack.yaml (issue #146).

FROM rust:1.83-bookworm AS builder
WORKDIR /build

# sqlx with `runtime-tokio-rustls` needs only OpenSSL headers from the base.
RUN apt-get update && apt-get install -y --no-install-recommends pkg-config libssl-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy crate sources. The migrations directory is embedded by sqlx::migrate!
# at compile time via include_str!, so it must be present during the build.
COPY services/explorer-indexer/Cargo.toml services/explorer-indexer/Cargo.lock ./
COPY services/explorer-indexer/src ./src
COPY services/explorer-indexer/migrations ./migrations

RUN cargo build --release --bin indexer

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libssl3 \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /build/target/release/indexer /usr/local/bin/indexer
ENTRYPOINT ["/usr/local/bin/indexer"]
