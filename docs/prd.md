# Robot Money — Product Requirements

> Scope: this PRD describes **what Robot Money is** to its users — what
> they do, what they get, what we promise. It is atemporal: it
> specifies the product, not the order in which pieces ship and not
> how they are built. Architecture, contract surfaces, signing paths,
> tooling, schemas, and other implementation details live in
> `docs/architecture.md` (security architecture) and
> `docs/implementation-plan.md` (build slice). Implementation status
> lives in the git history and the implementation plan;
> `docs/definitions.md` is the canonical glossary;
> `docs/project-roadmap.md` is deprecated (kept for historical
> reference only).

## 1. Product

Robot Money is a treasury platform for the agent economy. Idle USDC
held by AI agents, autonomous machines, and human depositors can be
allocated into a family of vaults:

- a stable-yield vault,
- a protocol-asset vault,
- an agent-token vault,
- and future thematic vaults such as RWA or commodity exposure.

Each vault issues its own receipt token whose value tracks that
vault's assets. Depositors can choose one vault directly or deposit
through the Portfolio Router, which allocates across active vaults
according to protocol-token-governed weights and exposes a composite
view of the resulting portfolio position.

The first governance surface is narrow: `$ROBOTMONEY` holders vote on
the Portfolio Router's target weights across active vaults. The protocol is
observable end-to-end: anyone can see which vaults exist, what each
vault holds, the current router weights, and how those weights were
approved.

## 2. Users

- **Autonomous depositors.** AI agents and machines holding USDC that
  want bounded access to one or more treasury strategies without
  bespoke per-protocol setup.
- **Human depositors.** Individuals seeking clear, selectable exposure
  to stable yield, protocol assets, agent-token baskets, or the
  Portfolio Router-managed composite allocation.
- **Token holders.** Holders of `$ROBOTMONEY` who vote on the
  Portfolio Router's multi-vault allocation weights and who benefit from
  buyback-and-burn supply reduction funded by protocol revenue.
- **Integrators.** Builders embedding Robot Money into their own
  agent runtimes or treasuries.

## 3. Promises to the user

1. **One transfer, chosen exposure.** A single USDC deposit enters
   either a selected vault or the Portfolio Router. Depositors do not
   need to manually execute the underlying strategy legs.
2. **Synchronous redemption.** Withdrawals settle in one transaction.
   No cooldowns, no two-step claims, no unbonding windows.
3. **Two-audience parity.** Humans and agents can perform the same
   operations — deposit, withdraw, observe, govern — through
   audience-appropriate surfaces.
4. **No-config defaults.** First-time use does not require manual
   tuning. The product picks safe defaults; advanced users can
   override.
5. **Honest failures.** When something cannot be done, the user is
   told why. When something partially succeeds, the user is told
   exactly what happened. There are no silent failures.
6. **Governance-driven router weights.** `$ROBOTMONEY` holders vote
   on the Portfolio Router's target weights across active vaults on a published
   cadence. Other governance surfaces are out of scope until specified
   separately.
7. **Allocation transparency.** The current allocation, recent
   performance, vault registry, Portfolio Router weights, and
   governance state are observable to anyone, in real time.

## 4. What users do

### 4.1 Autonomous treasury sweep

An autonomous business — a SaaS run by agents, a machine selling its
output over a payment rail, a fleet of devices generating micro-revenue
— accumulates USDC. It periodically sweeps the surplus above an
operator-defined working reserve into Robot Money. The selected vault
or Portfolio Router allocation puts those assets to work while idle.
When the business needs to pay vendors, refund customers, or reinvest,
it withdraws.

What the operator wants: predictable handling of cash that would
otherwise sit idle, with bounded risk per transaction and explicit
control over whether an agent may use a fixed vault, the Portfolio
Router, or both.

What we promise: deposits and withdrawals settle synchronously; the
agent's spending is bounded by per-agent and per-vault caps the
depositor sets; the depositor is the sole authority over her own agent
and can pause, update policy, or revoke it at any time without
third-party involvement. The Robot Money team has no runtime authority
over any depositor's agent — the only on-chain role the team retains
is contract upgrade and protocol-wide incident response.

### 4.2 Human depositor with delegated monitoring

An individual deposits USDC into a vault or into the Portfolio Router
that allocates across several vaults. They check in periodically —
through the web app, or by asking an LLM — to see how each position
has performed and whether the current router-weight vote is worth
weighing in on.

What the depositor wants: one place to park USDC, a clear choice of
exposure profiles, a clear view of where assets are allocated, and a
vote in how the Portfolio Router balances exposure across vaults.

What we promise: vault-specific receipt tokens, optional composite
views for Portfolio Router exposure, simple deposit/withdraw flows,
real-time visibility into allocation and performance, and governance
participation.

### 4.3 Token holder participating in governance

A `$ROBOTMONEY` holder votes on the Portfolio Router's target weights
across active vaults on published cadences. Protocol revenue funds
buyback-and-burn, reducing the token supply over time.

What the holder wants: a voice in how the product-level composite
allocation balances stable-yield, protocol-asset, agent-token, and
future thematic vault exposure, plus protocol value capture without
needing to be a depositor.

What we promise: open and on-chain voting, published cadences,
observable buyback execution.

## 5. Product surfaces

### 5.1 Vault family

- A registry of Robot Money vaults, each with a mandate, accepted
  asset, receipt token, caps, fees, risk label, and current status.
- Initial vault categories:
  - stable yield,
  - protocol assets such as ETH, BTC, and SOL exposure,
  - agent-economy tokens,
  - future RWA or commodity exposure where the legal and execution
    model is acceptable.
- Each vault is independently observable and independently pausable.
- A vault can be retired without retiring the entire product. Retired
  vaults stop accepting deposits while preserving redemption rights
  wherever possible.

### 5.2 Vaults, Portfolio Router, and composite view

- **Single-vault deposit.** A depositor chooses one vault and receives
  that vault's receipt token.
- **Portfolio Router deposit.** A depositor deposits through the
  Portfolio Router contract. The Portfolio Router allocates across
  active vaults according to the current RM-governed target weights.
- **Composite view.** The product shows router exposure as one
  composite position while preserving drill-down into each underlying
  vault, receipt balance, weight, valuation, and fee.
- **Receipt tokens.** Every vault receipt received through direct or
  Portfolio Router deposits is visible to wallets, dashboards, and
  agent clients.
- **No hidden routing.** A deposit preview shows the destination
  vaults, current Portfolio Router weights, estimated receipts, fees,
  and any unavailable leg before the user or agent signs.

### 5.3 Vault categories

- **Stable-yield vault.** USDC routed across diversified stable-yield
  venues so no single venue is a single point of failure.
- **Protocol-asset vault.** Exposure to major network assets, initially
  expected to include ETH, BTC, and SOL where chain and venue support
  make execution practical.
- **Agent-token vault.** Exposure to the agent economy. Inclusion and
  asset-selection mechanics are out of scope until a separate
  governance specification is approved.
- **RWA / thematic vaults.** Future vaults for narrative or
  macro-themed exposure, such as equity-index or commodity-linked
  strategies, only after their legal, liquidation, oracle, and user
  disclosure requirements are specified.

### 5.4 Agent-callable vault access

- Agents can read the vault registry, inspect vault and Portfolio
  Router health, and deposit only into vaults or the Portfolio Router
  when allowed by their depositor-owned policy.
- A depositor authorizes an agent under her wallet, sets maximum
  amount per payment, maximum amount per window, valid-until, share
  receiver, and allowed destination vaults or Portfolio Router access.
- Agent policies can allow:
  - one fixed vault,
  - a bounded set of vaults,
  - Portfolio Router deposits,
  - or both fixed-vault and Portfolio Router deposits.
- Agents cannot add vaults, change vault mandates, change their own
  share receiver, raise their own caps, alter Portfolio Router weights, or
  bypass disabled vaults.
- Agent clients must read before writing: vault registry, vault
  status, Portfolio Router weights, Portfolio Router status, agent
  policy, allowance, balance, and projected cap usage are checked
  before a signature is produced.

### 5.5 Treasury controls

- Two emergency switches:
  - a reversible operational pause, and
  - a permanent shutdown that disables further deposits while
    preserving redemption rights.
- Deposit caps are enforced at the vault level, Portfolio Router level, and
  agent-policy level.
- Synchronous deposit and withdrawal remain the default product
  promise. Any vault that cannot support synchronous redemption must be
  labeled separately and cannot be included in Portfolio Router
  allocations until that user promise is changed.

### 5.6 Governance and the `$ROBOTMONEY` token

- Fixed-supply governance token.
- The only governance vote specified for the application completeness
  phase is the Portfolio Router weight vote: holders vote on target
  weights across active vaults.
- RM voting does not currently govern vault onboarding, vault
  retirement, per-vault constituents, per-vault strategy selection, or
  agent permissions.
- The token does **not** entitle holders to treasury returns; it
  entitles them to direct participation in Portfolio Router allocation
  weights.
- Protocol revenue funds buyback-and-burn of `$ROBOTMONEY`.
- Vote results and execution are observable on-chain.

### 5.7 Fees

The protocol levies fees per vault or Portfolio Router path, each set within
published bounds:

- **Management fee** — a percentage of treasury value, accrued
  continuously.
- **Swap-fee share** — a percentage of swap fees earned on vault
  trading activity.
- **Exit fee** — a percentage of value applied to redemptions and
  withdrawals; included in the amount a depositor sees as their
  net-out.

The fee recipient is administered by the protocol's multisig.

### 5.8 Autonomous-agent access

Autonomous agents can deposit, withdraw, and observe the treasury
through a programmatic interface. Each depositor is the sole
authority over her own agent: she authorizes the agent under her
wallet, sets per-agent and per-vault spending bounds, chooses allowed
destination vaults and whether Portfolio Router deposits are allowed,
and pauses or revokes the agent at any time. No third party —
including the Robot Money team — signs or gates these calls. See
`docs/architecture.md` for the security architecture and
`docs/implementation-plan.md` for the agent client.

### 5.9 Human-facing web application

- Public dashboards: vault registry, vault state, Portfolio Router weights,
  current composition, performance, and history.
- Connect-wallet flow for deposits, withdrawals, and governance
  participation.
- Governance UI: active proposals, vote casting, vote history.
- Observability for buybacks and protocol revenue.

### 5.10 Allocation transparency

- Real-time, public allocation reporting across vaults, Portfolio
  Router weights, and externally delegated assets where applicable.
- Per-strategy attribution: which venue, what weight, what valuation.
- The same view is available to humans (web app) and to agents
  (programmatic interface).

### 5.11 Application completeness surfaces

- **Contracts.** Active vault contracts, a Portfolio Router contract that
  allocates deposits by RM-governed weights, and read surfaces for
  vault registry, Portfolio Router weights, portfolio position,
  composite view, previews, and execution results.
- **CLI.** Agent-safe commands to read vaults, read Portfolio Router
  weights, preview Portfolio Router deposits, deposit into allowed
  vaults or the Portfolio Router, and report portfolio positions.
- **Agent skills.** Skill instructions that require read-first
  inspection of vaults, Portfolio Router weights, policy, allowance,
  balance, and cap usage before any write.
- **Dapp UX.** Human-facing screens for vault registry, single-vault
  deposit/withdraw, Portfolio Router deposit/withdraw, composite
  allocation view, router-weight voting, and transaction previews.

## 6. Promises about quality

- **Stable interfaces.** Programmatic surfaces are versioned;
  breaking changes are announced and documented.
- **Helpful errors.** When an operation cannot proceed, the user
  receives an explanation in product terms (e.g. "deposit cap
  reached," "treasury paused"), not raw technical output.
- **Reliable connectivity.** The product handles transient network
  failures gracefully without user intervention.
- **Pre-flight checks.** Operations are validated before they are
  committed; users are warned of likely failures before incurring
  cost.
- **Auditability.** Every state change is observable on-chain;
  off-chain decisions (governance, delegated allocations) are
  observable through the same surfaces.

## 7. Trust

- **Vaults.** Vault contracts whose upgrade authority, if any, is held
  by the Robot Money team multisig. The team's only on-chain authority
  is contract upgrade and protocol-wide kill switches (pause,
  permanent shutdown) for incident response; the team has no runtime
  authority over any individual depositor's agent.
- **Execution.** Slippage, oracle, liquidity, and quote-freshness
  bounds apply to every vault trade and Portfolio Router leg. A failed
  Portfolio Router leg must either revert the whole deposit or be
  explicitly surfaced as a partial fill before signing.
- **Custody.** Vault assets are held by the destination vaults or their
  adapters. Receipt tokens are held by the depositor, the depositor's
  chosen share receiver, or the Portfolio Router only if a later
  architecture explicitly requires custody for composite reporting.
- **Governance.** Vote results are public and on-chain. The path
  from an RM-token vote to Portfolio Router weight execution is bounded
  by the published router-weight rules. Other governance actions are
  out of scope until specified separately.
- **Autonomous-agent signing.** Specified separately in
  `docs/architecture.md`; out of PRD scope.
- **Security posture.** The exhaustive web/web3/blockchain attack
  taxonomy and our per-row assessment is in
  `docs/security-model.md`.

## 8. Out of scope

- **Custodial key management.** Robot Money does not hold private
  keys for any user.
- **General-purpose wallet UX.** The web app is a depositor and
  governance interface, not a wallet.
- **Fiat on-ramps and off-ramps.** USD ↔ USDC conversion is
  out-of-band.
- **Direct user calls into underlying venues.** Robot Money flows go
  through vaults and the Portfolio Router, not direct venue calls.
- **RM governance over vault internals.** The current RM vote controls
  Portfolio Router weights only; it does not govern per-vault asset
  selection or strategy internals.
- **Agent-controlled vault creation.** Agents can request or lobby for
  inclusion through off-chain processes, but cannot create vaults or
  add assets by calling the agent deposit interface.
- **Hosted custody or hosted signing services.**
