# Product Requirements Document

## 1. Problem Statement

Robot Money helps autonomous agents, machine-operated businesses, and
human depositors put idle USDC to work without requiring each user to
manually assemble, monitor, and rebalance treasury exposure across
multiple venues or strategy categories.

Primary users need a treasury product that supports direct vault
selection, a managed multi-vault allocation, transparent performance and
allocation reporting, and bounded autonomous-agent access. The product
is better than manual treasury management because users can choose an
exposure profile, preview the consequences of a deposit or withdrawal,
and rely on consistent controls across human and agent-operated flows.

## 2. Goals and Success Metrics

- Depositors can deposit USDC into a selected vault or a Portfolio
  Router allocation with a clear preview of destination, fees, expected
  receipts, and unavailable legs.
- Depositors can withdraw synchronously from eligible vaults and
  Portfolio Router paths.
- Autonomous depositors can authorize agent activity with user-defined
  limits, destinations, recipients, and expiration.
- Addresses with admin-assigned voting power can vote on target weights
  for the Portfolio Router allocation. (Current governance is an
  admin-weighted MVP mock; token-holder voting is a future goal.)
- Any user can inspect vault availability, allocation weights,
  performance, fees, governance state, and execution results.
- Product failures are explicit: users receive a product-level reason
  when an operation cannot proceed or only partially succeeds.

Success is measured by:

- successful deposit and withdrawal completion rate;
- percentage of attempted operations that provide a preview before user
  approval;
- percentage of failed operations that return a clear product reason;
- autonomous-agent activity that remains within depositor-defined limits;
- governance participation in allocation-weight votes;
- user visibility into allocation, performance, fees, and state changes.

## 3. User Roles

- **Autonomous depositor.** An AI agent, autonomous machine, or
  agent-operated business that uses depositor-approved treasury
  permissions to deposit, withdraw, and observe positions.
- **Human depositor.** A person who deposits USDC, chooses vault or
  Portfolio Router allocation exposure, withdraws funds, and monitors
  positions.
- **Governance voter.** An address with admin-assigned voting power
  (current MVP) who votes on target weights for the Portfolio Router
  allocation and observes protocol value capture. Token-holder voting
  is a future goal once a real token snapshot or voting-power source
  is integrated.
- **Integrator.** A builder who embeds Robot Money treasury actions and
  reporting into an agent runtime, treasury workflow, or external
  product.
- **Protocol operator.** A limited operations role responsible for
  product-wide incident response and published administrative controls,
  without authority over individual depositor agent policies.

Access expectations:

- Depositors can create positions, withdraw from their positions,
  define agent permissions for their own agents, update those
  permissions, and revoke those permissions.
- Autonomous depositors can act only within permissions set by the
  depositor who authorized them.
- Addresses with admin-assigned voting power can participate in
  allocation-weight governance and view governance history. (Current
  governance is admin-weighted MVP; token-holder voting is a future
  goal.)
- Integrators can read public product state and submit user-authorized
  actions.
- Protocol operators can use product-wide safety controls, but cannot
  create, expand, or redirect an individual depositor's agent policy.
- Authorization depends on relationship: a depositor controls only their
  own positions, agent policies, recipients, and permissions.

## 4. User Stories

- As an autonomous depositor, I want to sweep idle USDC into an approved
  treasury destination so that surplus operating funds can earn exposure
  without giving the agent unrestricted control.
- As a human depositor, I want to choose a vault or Portfolio Router
  allocation and preview the result before approving so that I
  understand where my funds go and what I receive.
- As a human depositor, I want to withdraw synchronously from eligible
  positions so that funds are available when needed.
- As an address with admin-assigned voting power, I want to vote on
  Portfolio Router target weights so that I can influence how the
  composite treasury exposure is balanced. (Token-holder voting is a
  future goal; current governance is admin-weighted MVP.)
- As an integrator, I want stable read and action surfaces so that agent
  runtimes and treasury tools can embed Robot Money safely.
- As a protocol operator, I want narrow product-wide safety controls so
  that incidents can be contained without taking control of user agents
  or positions.

## 5. Core Workflows

### Human Depositor Deposit

1. The depositor connects a wallet or other supported account surface.
2. The depositor reviews available vaults, risk labels, fees,
   availability, and the Portfolio Router allocation option.
3. The depositor enters an amount and chooses a destination.
4. The product previews destination weights, expected receipts, fees,
   net amount, and unavailable legs.
5. The depositor approves the operation.
6. The product reports the result and updates the depositor's position
   view.

### Human Depositor Withdrawal

1. The depositor selects a position.
2. The product previews source, amount, fees, net amount, recipient, and
   any limitations.
3. The depositor approves the withdrawal.
4. The product settles the withdrawal synchronously for eligible paths
   and reports the result.

### Autonomous Treasury Sweep

1. A depositor authorizes an agent and defines allowed destinations,
   maximum amounts, recipients, and expiration.
2. The agent observes available balance, policy limits, destination
   state, and allocation state.
3. The agent requests a deposit or withdrawal within the depositor's
   limits.
4. The product refuses requests outside policy, unavailable
   destinations, or insufficient balances.
5. Approved activity settles and is reported to the depositor and agent.

### Allocation Governance

NOTE: Current governance is admin-weighted MVP (RouterGovernance.sol).
Voting power is assigned by ADMIN_ROLE; proposal creation is
ADMIN_ROLE-only. Token-holder voting is a future goal.

1. An address with admin-assigned voting power reviews active
   allocation-weight proposals, target weights, timing, and expected
   impact.
2. The voter votes.
3. The product publishes vote outcome, execution state, and resulting
   allocation weights.
4. Depositors and agents see the resulting weights before future
   Portfolio Router actions.

### Integrator Read And Action Flow

1. The integrator reads vault registry, allocation weights, position
   state, fees, and availability.
2. The integrator presents product-level previews and refusal reasons to
   its user or agent.
3. User-authorized actions are submitted only after the relevant preview
   and permission checks.
4. Results are returned with enough detail for downstream reporting.

Common edge cases:

- selected destination is paused, retired, full, or unavailable;
- requested amount exceeds depositor, vault, allocation, or agent limits;
- withdrawal path cannot meet synchronous settlement requirements;
- a Portfolio Router allocation leg is unavailable, causing the whole deposit to revert;
- account balance or approval is insufficient;
- agent permission is expired, revoked, or scoped to a different
  destination;
- governance proposal expires, fails, or is not executable;
- external market, liquidity, valuation, or compliance constraints make
  a strategy temporarily unavailable.

## 6. Entity Lifecycle

- **Vault.** Proposed -> active -> paused -> active; active -> retired;
  retired -> redeemable archive when redemptions remain available.
- **Portfolio Router allocation.** Draft weights -> active vote ->
  approved weights -> applied weights; active vote -> rejected or
  expired.
- **Depositor position.** No position -> previewed deposit -> active
  position -> previewed withdrawal -> reduced or closed position.
- **Agent policy.** Draft -> active -> updated -> paused or revoked;
  active -> expired when its validity window ends.
- **Agent action.** Requested -> previewed -> approved -> settled;
  requested or previewed -> refused; approved -> partially settled only
  when the user-facing preview allows partial execution.
- **Governance proposal.** Draft -> open for voting -> approved or
  rejected -> applied or expired.
- **Fee schedule.** Proposed -> published -> active -> superseded.
- **Incident control.** Normal -> paused -> normal; normal or paused ->
  shutdown when new deposits must stop while preserving withdrawal
  rights where possible.

## 7. Integration Needs

- **Wallet or account authorization.** Triggered when a depositor
  connects, approves a deposit or withdrawal, manages an agent policy, or
  votes.
- **Digital asset transfer and settlement.** Triggered by deposits,
  withdrawals, fee collection, allocation changes, and buyback activity.
- **Market access and valuation.** Triggered when vaults need asset
  pricing, liquidity checks, performance reporting, or strategy
  execution.
- **Governance participation.** Triggered by proposal creation, vote
  casting, vote tallying, weight publication, and execution reporting.
- **Public state indexing and reporting.** Triggered by deposits,
  withdrawals, policy changes, governance actions, allocation changes,
  fee events, and incident controls.
- **Agent runtime integration.** Triggered when an authorized agent reads
  product state, previews an action, submits an action, or receives a
  refusal reason.
- **Compliance and disclosure support.** Triggered by new vault
  categories, restricted exposure types, user disclosures, incident
  reporting, and jurisdiction-specific requirements.

## 8. Out of Scope

- Custodial private-key management for users.
- General-purpose wallet functionality beyond Robot Money treasury and
  governance workflows.
- Fiat on-ramps and off-ramps.
- Direct user interaction with underlying strategy venues outside Robot
  Money vault and allocation flows.
- Agent-created vaults, agent-created assets, or agent-controlled
  governance changes.
- Token-holder governance over vault internals, per-vault asset
  selection, strategy selection, fees, or individual agent permissions.
- Hosted custody or hosted signing services.
- Vault categories whose legal, liquidity, valuation, and disclosure
  requirements are not specified.

## 9. Constraints

- Deposits and withdrawals must provide a preview before user approval.
- Eligible withdrawals must settle synchronously.
- Product surfaces must expose fees, net amounts, destinations,
  recipients, limits, and refusal reasons in user-facing language.
- Autonomous-agent access must remain bounded by depositor-defined
  amount limits, destination limits, recipients, and expiration.
- A depositor must remain the authority over their own agent policy.
- Product-wide safety controls must not grant operators authority to
  redirect user funds or expand an individual agent's permissions.
- The Portfolio Router must expose target weights, active weights,
  governance state, and historical outcomes.
- Vault and Portfolio Router fee structures are limited to three
  classes: management fee, swap-fee share, and exit fee. Each fee
  class, its rate, and its recipient must be disclosed before user
  approval. In the current phase only exit fees are implemented;
  management fee and swap-fee share are deferred to a future phase.
- Vaults must disclose risk labels, fees, caps, availability, and
  retirement or pause state.
- Accessibility expectations apply to human-facing flows, including
  readable previews, keyboard-accessible controls, and clear status and
  error messaging.
- New exposure categories must satisfy legal, liquidity, valuation,
  redemption, and disclosure requirements before being made available to
  depositors.

## 10. Prior Art

The following protocols informed the Robot Money architecture. Each is
referenced in open questions or build-vs-buy decisions elsewhere in this
document.

### Veda

Veda is the closest published reference to the Portfolio Router model.
It manages depositor USDC across a curated set of underlying ERC-4626
vaults and issues a single composite receipt. Governance or an operator
sets target weights; the protocol routes deposits accordingly.

Robot Money diverges on one key point: Veda issues an outer share token
wrapping the underlying vault positions. The Robot Money Portfolio Router
does not — depositors receive underlying vault receipts directly and the
portfolio position is a reporting concept over those receipts, not a
separate on-chain claim. This preserves depositor visibility into each
vault and avoids creating a hidden custody layer (see
`docs/architecture.md` §2.2).

### Yearn V3

Yearn V3 is the architectural reference for the Robot Money vault and
adapter layer. A Yearn V3 vault accepts deposits into a single ERC-4626
contract and routes assets across multiple pluggable "strategies"
(yield venues). The RobotMoneyVault reproduces this pattern: an
IStrategyAdapter interface normalizes each venue, deposits route across
active adapters by equal-weight target, and a keeper-triggered rebalance
corrects drift. The asymmetric pause model (EMERGENCY_ROLE pauses,
ADMIN_ROLE unpauses) is also borrowed from Yearn's security design.

### Giza and Zyfai

Giza and Zyfai are yield optimization protocols on Base that allocate
USDC across Aave, Compound, and Morpho by utilization-driven or
off-chain-optimized weight models. Both are candidates for the stable-yield
vault's adapter layer if the team revisits the decision to maintain
custom adapters in-house (build-in-house is decided; see issue #470). The current architecture is built
to support either model: swapping a custom adapter for a Giza- or
Zyfai-managed allocation requires only deploying a new IStrategyAdapter
wrapper, not changing the vault contract.

### Morpho Gauntlet USDC Prime

A curated ERC-4626 vault on Base, managed by Gauntlet, that optimally
allocates USDC across Morpho Blue lending pools. It is itself a vault —
the MorphoAdapter holds Morpho Gauntlet shares, not raw Morpho Blue
positions — which means depositors benefit from Gauntlet's active
allocation without the stable-yield vault needing to manage Morpho Blue
directly. This two-layer structure (Robot Money vault → Morpho Gauntlet
vault → Morpho Blue pools) is a practical example of the multi-vault
nesting the Portfolio Router generalises.

## 11. Vault Catalog

This section specifies the product properties of each Robot Money vault
category. Technical implementation details live in `docs/architecture.md`
and the contract source. The catalog is the product-level commitment:
risk label, fee structure, accepted asset, withdrawal model, and status.

### 11.1 Stable Yield Vault

| Property | Value |
| --- | --- |
| Name | Robot Money USDC |
| Receipt token | rmUSDC |
| Accepted asset | USDC (Base, 6 decimals) |
| Risk label | STABLE_YIELD |
| Exposure | USDC yield across Morpho Gauntlet USDC Prime, Aave V3, Compound V3 on Base |
| Allocation model | Equal-weight across active adapters; keeper-triggered rebalance |
| Exit fee | Configurable 0–1%; 0.1% at launch |
| Management fee | Not implemented in current phase |
| Swap-fee share | Not implemented in current phase |
| Withdrawal | Synchronous; single transaction |
| TVL cap | Configurable; launch cap TBD (see §2, §3.4) |
| Per-deposit cap | Configurable |
| Status | Deployed on Base mainnet |

The stable-yield vault is the launch vault and the only vault currently
eligible for Portfolio Router allocation. Its synchronous redemption
guarantee is met through proportional withdrawal across all active
adapters in a single transaction. If any adapter cannot fulfil its
proportional share, the vault attempts to cover the shortfall from the
remaining adapters before reverting.

### 11.2 Protocol Asset Vault

| Property | Value |
| --- | --- |
| Name | Robot Money Protocol |
| Receipt token | rmPROTO |
| Accepted asset | USDC (Base, 6 decimals) |
| Risk label | VOLATILE |
| Exposure | Basket of protocol assets (wETH, cbBTC, wSOL) via Uniswap V3 swaps |
| Allocation model | Equal-weight across active basket assets at deposit time |
| Exit fee | Configurable 0–1% |
| Withdrawal | Synchronous; depends on swap liquidity |
| Status | Prototype — not audited, not Router-eligible |

Deposits swap USDC into basket assets; withdrawals swap back. NAV is
denominated in USDC and priced from a Uniswap V3 TWAP over an
admin-configured per-asset window; `slot0` is not consulted on hot
paths. Swap slippage means actual withdrawal proceeds may differ from
the preview by up to the configured slippage bound. Router eligibility
remains blocked by the unresolved intra-vault rebalancing model
(§3.15); concrete subclasses must additionally certify pool
cardinality and per-asset window prerequisites before opting out of
prototype status.

### 11.3 Agent Token Vault

| Property | Value |
| --- | --- |
| Name | Robot Money Agent Tokens |
| Receipt token | rmAGENT |
| Accepted asset | USDC (Base, 6 decimals) |
| Risk label | SPECULATIVE |
| Exposure | Admin-curated basket of agent-economy tokens via Uniswap V3 swaps |
| Allocation model | Equal-weight across shortlisted tokens at deposit time |
| Exit fee | Configurable 0–1% |
| Withdrawal | Synchronous; depends on swap liquidity |
| Status | Prototype — not audited, not Router-eligible |

Shortlist curation is admin-controlled in the prototype. The production
model (bribery-based or RM-token inclusion vote) is unresolved (§1.3,
§1.4, §3.15). TWAP pricing is shipped via the basket-vault base.
Router eligibility remains blocked by unresolved shortlist governance
and the intra-vault rebalancing model.

### 11.4 RWA / Thematic Vault

| Property | Value |
| --- | --- |
| Status | Future — not specified |

Flagged for narrative value (SP500 perp via Hyperliquid, commodities).
Requires separate legal, oracle, liquidation, disclosure, and redemption
work before inclusion in Portfolio Router allocations (a business/launch
decision tracked outside this repository).

# Robot Money — Open Questions

Unresolved **product and engineering** questions derived from reading the three source documents kept locally under `docs/papers/`:

- `Robot-Money-Whitepaper-v01` (Protocol Specification v0.1, February 2026)
- `robot_money_plan_v4` (Gen Ventures × ZHC plan)
- `robot_money_prd` (PRD MVP v1.0, March 2026)

> **Source docs are confidential and local-only.** The PDF/docx originals and their verbatim markdown conversions are not committed to this repository (see `.gitignore`). This document is the public surface; quotations and section references below are the only public reflection of the source-doc contents.

This document tracks only the questions that are **still open and product/engineering-owned**, grouped by topic. Items are tagged with their original `§x.y` identifier, retained as a stable anchor so existing cross-references from other docs still resolve; the identifiers no longer imply order.

> **Out of scope here:** resolved contradictions and their code evidence live in **issue #470** (and are asserted as facts in the PRD body and `docs/architecture.md` §2–4, §10). Business, legal, pricing, tokenomics, agent-persona, audit, multi-chain, and other go-to-market/launch decisions are **tracked outside this repository**.

---

## 1. Product topics

### 1.A Governance and voting

**Router-weight vote rules (§3.9).** The implemented router-weight vote still needs quorum, cadence, threshold, execution, and fallback rules. In particular, no doc addresses the quorum cliff — if the vote falls just below quorum the default allocation executes; just above, voted weights execute — nor any smoothing (e.g. a continuous blend between voted and default weights as quorum scales) to avoid week-to-week governance whiplash. **TBD.**

**Governance tiers (§1.5).** No tier system exists today; `RouterGovernance` is flat (admin-assigned voting power now, RM-balance-linear later). The source PRD's four tiers (Observer / Participant / Analyst / Strategist) plus a 14-day activity gate are unbuilt. **Open question for the product owner:** do governance tiers and an activity gate matter to the MVP at all, or only to a future agent-token shortlist surface? Until ruled on, treat tiers as out of current scope but undecided as product direction — do not build the four-tier machinery.

**Agent-token shortlist ownership (§1.3).** For the current product the agent-token vault shortlist is admin/protocol-curated (`contracts/vaults/AgentTokenVault.sol`). Unresolved is the long-term model: admin curation vs. `$RM`-token inclusion proposals vs. the designed-in bribery flow (agents lobby/pay `$RM` to push their token into the vault). The source PRD's inclusion-proposal / quorum / displacement / 15-token-cap machinery only applies if a bottom-up model is chosen. **TBD** — out of current router-weight governance scope.

**Shortlist vote mechanic (§1.4).** The implemented vote is bps allocation across active vaults for Portfolio Router weights (resolved, issue #470). Unresolved is the mechanic for any *future agent-token shortlist* vote: ranked-choice over the shortlist (whitepaper) vs. token-level bps allocation (source PRD). **TBD**, pending the §1.3 ownership decision.

### 1.B Agent-token vault internals

**Token eligibility / quant-filter methodology (§3.1).** The thresholds are defined ($10M mcap, 90 days, $100K volume, 500 holders) but not the *measurement methodology*: which oracle/aggregator, what averaging window, how disputes are resolved. The PRD mentions "CoinGecko + on-chain" with "consensus required if sources disagree" but does not specify rules. **TBD.** Not needed for the router-weight vote; required before agent-token shortlist governance ships.

**Trading authority and strategy (§3.2).** The whitepaper says the agent trades agent-economy tokens using on-chain signals (volume, holder distribution, treasury health, developer activity), but no doc specifies the trading strategy, position-sizing rules, stop-loss enforcement, or how losses are reported in NAV in real time. Trading authority, strategy, position sizing, and reporting remain **TBD** and are out of scope for Portfolio Router weight governance.

**Intra-vault rebalancing (§3.15).** Basket vaults (protocol-asset and agent-token) allocate new deposits equally across active assets at deposit time; existing positions are not touched when an asset is added or removed, creating drift. Three sub-questions are open:

- **Who triggers rebalancing?** Admin-initiated (keeper calls a rebalance function), keeper-automated on a cadence, or depositor-self-service.
- **What is the target?** Equal weight across current active assets, or a governed weight vector (which would require the basket to adopt router-weight-style governance)?
- **What are the cost and slippage constraints?** A full rebalance requires many swaps in sequence; slippage and fee cost are borne by all shareholders. The product must disclose rebalancing cost before it executes, or defer cost to depositors who trigger it at redemption.

Vault-level rebalancing is distinct from Portfolio Router weight updates, which allocate across vaults rather than within one. **TBD.** The prototype routes only new deposits into equal-weight positions; a `rebalance()` admin function and its cost-disclosure model must be specified before the agent-token vault can meet the PRD's transparent-performance requirement.

### 1.C Vault lifecycle and redemption

**Upgrade, migration, and retirement (§3.5).** The whitepaper says "no upgradeability — immutable contract," while Plan v4 and the PRD describe progressive expansion. The multi-vault architecture reduces pressure to mutate one monolithic vault — new exposure types can ship as new vaults and become active router destinations — but the exact upgradeability, migration, and retirement mechanics per vault and per router contract remain **TBD.**

**Withdrawal under basket-vault drawdown (§3.7).** The default product promise is synchronous withdrawal at NAV minus exit fee. No doc specifies what happens when a basket vault holds positions that cannot be unwound synchronously and a depositor wants to exit — forced sale, queued withdrawal, or NAV haircut. Vaults that cannot support synchronous redemption must be labeled separately and excluded from Portfolio Router allocations until the promise changes. Agent-token vault drawdown mechanics remain **TBD.**

### 1.D Operational trust and safety

**Multisig composition and trust (§3.4).** Vote results that drive weight updates must be executed under admin authority held by a multisig/timelock. No doc names signers, defines challenge-window dispute resolution, or specifies what happens if signers disagree with the published tally. **TBD.**

**Protocol-agent failure modes (§3.10).** A protocol agent that publishes shortlists, runs the default allocation, executes rebalances, and posts the public narrative is a single point of failure. No doc addresses what happens if it goes offline, is compromised, hallucinates a bad allocation, or its operator steps away; there is no agent-of-last-resort or emergency pause that names a controller. Partially avoided for current scope (the only specified vote is RM-token router weights, not protocol-agent-run shortlist selection), but agent-token shortlist and protocol-agent responsibilities remain **TBD.**

---

## 2. General research questions

Open-ended modeling and analysis that must be studied before the related product topic can be decided.

**Inclusion-attack economic bounds (§3.8).** The whitepaper argues the inclusion attack is self-punishing because attackers' `$RM` loses value if their token underperforms, but the magnitude is not modeled: how much `$RM` must an attacker hold to swing allocation, vs. the vault buy pressure produced, vs. expected `$RM` loss from underperformance? Without numbers, "self-punishing" is an assertion, not a proof. Requires economic modeling; applicable once RM governance controls agent-token inclusion or per-vault asset selection (§1.3). **Research open.**

---

## 3. Suggested resolution order

1. **Router-weight vote rules** — quorum, cadence, threshold, execution, fallback (§3.9).
2. **Portfolio Router implementation details** — contract API, preview semantics, failure behavior, receipt delivery, cap model, vote-to-weight execution.
3. **Agent-token vault internals** — shortlist ownership and vote mechanic, whether tiers are needed, token eligibility methodology, trading authority, intra-vault rebalancing, and the inclusion-attack modeling that gates them (§1.3, §1.4, §1.5, §3.1, §3.2, §3.8, §3.15).
4. **Vault lifecycle and operational trust** — upgrade/migration/retirement, basket-drawdown withdrawal, multisig composition, and protocol-agent failure modes (§3.4, §3.5, §3.7, §3.10).
