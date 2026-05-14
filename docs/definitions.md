# Robot Money — Definitions

This glossary defines product terms used across the PRD, architecture,
implementation plan, dapp, CLI, and agent skills. When another document
uses one of these terms, this file is the canonical meaning.

## Vault

A Robot Money vault is an individual strategy container. It accepts a
supported asset, deploys or manages that asset according to a specific
mandate, and issues a receipt token for deposits.

A vault is also a normalization layer. On-chain assets and venues have
heterogeneous interfaces: deposit methods, withdrawal methods, receipt
tokens, rebasing behavior, valuation math, liquidity constraints, and
reporting conventions differ across protocols. A well-designed vault
absorbs that heterogeneity and presents a predictable product surface:
deposit, withdraw, receipt, NAV, risk state, and performance.

Examples:

- Stable-yield vault.
- Protocol-asset vault.
- Agent-token vault.
- Future thematic or RWA vaults.

## Underlying Vault

An underlying vault is any individual Robot Money vault used as a
destination by the Portfolio Router.

## Vault Adapter

A vault adapter is an internal module used by one Robot Money vault to
connect that vault to an underlying strategy or venue.

Adapters are not vaults, are not Portfolio Router destinations, and are
not selected directly by users or agents. They sit inside a vault's
implementation and handle venue-specific operations such as deploying
USDC, withdrawing USDC, and reporting the vault's live value in that
venue.

Adapters are the venue-normalization layer inside a vault. They let a
vault speak to heterogeneous protocols without leaking those protocol
differences to users, agents, or the Portfolio Router.

Adding or changing a vault adapter is a privileged vault-management
operation and expands that vault's security and audit surface.

## Vault Receipt

A vault receipt is the token issued by an individual vault to represent
a depositor's claim on that vault.

Vault receipts are held by the depositor or the depositor's configured
share receiver. The Portfolio Router does not turn them into a separate
outer share token.

## Portfolio Router

The Portfolio Router is the outermost allocation contract. It accepts a
deposit request and routes it across active underlying vaults according
to the current RM-governed target weights.

The Portfolio Router is not a vault and does not issue shares. Users
receive the underlying vault receipts directly.

## Portfolio Position

A portfolio position is the user's aggregate position across multiple
vault receipts produced by Portfolio Router deposits.

The position is a product and reporting concept, not a separate share
token. It is computed from the user's underlying vault receipt balances,
current vault values, and current router weights.

## Composite View

The composite view is the UI, CLI, and agent-readable presentation of a
portfolio position as one allocation.

It must preserve drill-down into the underlying vaults, receipt
balances, weights, valuations, fees, and any unavailable leg.

## Router Weights

Router weights are the target allocation percentages the Portfolio
Router uses when splitting deposits across active underlying vaults.

Router weights are the only RM-token governance surface specified for
the current product scope.

## RM-Token Governance

RM-token governance means `$ROBOTMONEY` holders vote on router weights.

In the current product scope, RM-token governance does not control:

- vault onboarding,
- vault retirement,
- per-vault asset selection,
- per-vault strategy selection,
- fees,
- agent permissions,
- or user-specific portfolio positions.

## Agent Policy

An agent policy is the depositor-owned permission set for an autonomous
agent. It defines what the agent can do, including spend caps, expiry,
share receiver, allowed vaults, and whether Portfolio Router deposits
are allowed.

The depositor who authorizes the agent owns the policy. The Robot Money
team does not manage user agent policies at runtime.
