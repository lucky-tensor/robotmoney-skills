# Multi-stage build for the human dapp.
#
# Canonical: docs/implementation-plan.md §12 — Phase 6.
# Used by: docker-compose.full-stack.yaml (issue #146).
#
# Build args wire VITE_* env vars at build time (Vite inlines them into
# the static bundle). The runtime stage serves the built dist/ via
# `vite preview` so the same port (5173) is used in dev and in the
# containerized devnet.

FROM node:20-bookworm-slim AS builder
WORKDIR /build

ARG VITE_FORK_RPC_URL=http://localhost:8545
ARG VITE_EXPLORER_API_URL=http://localhost:8080
ARG VITE_GATEWAY_ADDRESS=0x0000000000000000000000000000000000000000
ARG VITE_VAULT_ADDRESS=0x0000000000000000000000000000000000000000
ARG VITE_GATEWAY_CODE_HASH_VERIFIED=false
ARG VITE_ENV_CLASS=fork
ARG VITE_USE_MOCK_WALLET=false
ARG VITE_BROWSER_KEYGEN=false
ARG VITE_HISTORY_PANE=false

ENV VITE_FORK_RPC_URL=$VITE_FORK_RPC_URL \
    VITE_EXPLORER_API_URL=$VITE_EXPLORER_API_URL \
    VITE_GATEWAY_ADDRESS=$VITE_GATEWAY_ADDRESS \
    VITE_VAULT_ADDRESS=$VITE_VAULT_ADDRESS \
    VITE_GATEWAY_CODE_HASH_VERIFIED=$VITE_GATEWAY_CODE_HASH_VERIFIED \
    VITE_ENV_CLASS=$VITE_ENV_CLASS \
    VITE_USE_MOCK_WALLET=$VITE_USE_MOCK_WALLET \
    VITE_BROWSER_KEYGEN=$VITE_BROWSER_KEYGEN \
    VITE_HISTORY_PANE=$VITE_HISTORY_PANE

COPY clients/dapp/package.json clients/dapp/pnpm-lock.yaml ./
RUN npm install -g pnpm@9 && pnpm install --frozen-lockfile

COPY clients/dapp ./
RUN pnpm run build

FROM node:20-bookworm-slim
WORKDIR /app
RUN npm install -g pnpm@9 vite
COPY --from=builder /build/dist ./dist
COPY --from=builder /build/vite.config.ts ./vite.config.ts
COPY --from=builder /build/package.json ./package.json
EXPOSE 5173
CMD ["npx", "vite", "preview", "--host", "0.0.0.0", "--port", "5173"]
