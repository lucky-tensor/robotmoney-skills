# Robot Money — Open Questions

Unresolved questions derived from reading the three source documents kept locally under `docs/papers/`:

- `Robot-Money-Whitepaper-v01` (Protocol Specification v0.1, February 2026)
- `robot_money_plan_v4` (Gen Ventures × ZHC plan)
- `robot_money_prd` (PRD MVP v1.0, March 2026)

> **Source docs are confidential and local-only.** The PDF/docx originals and their verbatim markdown conversions are not committed to this repository (see `.gitignore`). This document is the public surface; quotations and section references below are the only public reflection of the source-doc contents.

The docs were authored at different moments with different scopes and were not reconciled before being collected here. This document captures (1) cross-document contradictions that require a product decision, (2) open questions the source docs explicitly flag, and (3) gaps that none of the docs address.

Where applicable, each item carries a **Product owner input** note capturing direction conveyed verbally by the product owner (Lex Sokolin, 2026-05-06). These are stated intentions, not yet written into specs the repo can verify, but they reflect current thinking. Treat them as one input — not a final resolution.

Each item may also carry a **Best current answer** note. These are the
working answers from current product planning, including the 2026-05-14
application-completeness discussion. They preserve the original
questions while making the present best guess explicit. Items marked
**TBD** remain unresolved.

---

## 1. Cross-document contradictions

These are points where two or more documents make incompatible claims. Each needs a decision before any of the docs can be published externally as a coherent set.

### 1.1 One token or two?

- **Whitepaper**: single `$ROBOTMONEY`, fixed 1B supply via Clanker v4, LP locked until 2100. Value accrues only through buyback-and-burn from prop-wallet realized gains. Explicitly: "no inflationary yield … staking $ROBOTMONEY does not earn more $ROBOTMONEY."
- **Plan v4**: two-token path. `$RM v1` (Clanker community token) → `$RM v2` (custom contract with **staking and fee distribution**), v1→v2 exchange with early-mover bonus.
- **PRD**: single `$RM`, governance only. No v1/v2.

**Question:** Is there a v2 protocol token with staking and fee distribution, or is the burn-only Clanker token the permanent design?

**Why it matters:** Plan v4's "fee distribution to stakers" directly contradicts the whitepaper's burn-only accrual. The two cannot both be true. This also determines whether early `$RM` buyers face dilution/migration risk.

**Product owner input:** Token is "a voting heartbeat for AIs to contribute to allocation voting and try to bribe in their own assets to vaults." Framed as governance + a designed-in bribery flow, not a yield-bearing instrument. Described as a "separate build attempt … described in specs" not in this repo. Consistent with single-token, governance-only.

**Best current answer:** Single `$ROBOTMONEY` / RM governance token. For the current product scope, RM holders vote only on Portfolio Router target weights across active vaults. No v1/v2 migration, staking, or fee-distribution model is specified here. Detailed tokenomics, supply, launch terms, Clanker terms, and buyback mechanics remain **TBD**.

### 1.2 Vault: three-bucket from launch, or stables-first?

- **Whitepaper**: 33/33/33 stables / agent-token trading / revenue tokens **from day one**. Monthly bucket-weight rebalance.
- **Plan v4**: stables-only genesis vault in Phase 1. Robot-coin baskets in Phase 3 (Weeks 8–16). Protocol/DeFi tokens Phase 4.
- **PRD**: vault is referred to as future ("before the vault ships"); CFO Feed exists partly to fill the gap.

**Question:** What is in the vault on day one — three buckets or a single-strategy stables vault?

**Why it matters:** Affects launch-week TVL targets, smart-contract scope, audit surface, and the GTM narrative ("managed three-bucket exposure" vs. "stable yield, expanding").

**Product owner input:** Architecture is multi-vault, not multi-bucket-in-one-vault: *"multi-vault of n vaults, and then receipt tokens for vaults, and then that maybe or maybe not wrapped into a vault. Perhaps people can opt into different mixes of exposure."* Specific vaults named: stables ("sort of done"; Giza and Zyfai mentioned as additional strategy candidates), a protocol vault (ETH/BTC/SOL), an agent-token vault ("not done", with the voting/bribery use case attached), and a possible RWA vault (SP500 via a Hyperliquid position; commodities). Veda was considered as an off-the-shelf provider; the team chose to build in-house. Reframes the question: not three-bucket-vs-stables-first but a sequence of separate vault contracts with optional meta-vault wrapping (see §3.11, §3.12).

**Best current answer:** Neither three-bucket-in-one-vault nor stables-only permanent product. The application-completeness target is a multi-vault system: stable-yield vault, protocol-asset vault, agent-token vault, and future thematic/RWA vaults. A Portfolio Router allocates deposits across active vaults according to RM-governed router weights.

### 1.3 Shortlist curation: top-down or bottom-up?

- **Whitepaper**: the protocol's agent runs the quant screen and **publishes** the shortlist of 10–15 tokens. Holders only rank.
- **PRD**: any Analyst-tier (100M `$RM`) agent **proposes** tokens. 48h Approve/Reject inclusion vote at 3% quorum. 15-token cap with displacement rules.

**Question:** Who decides what is on the shortlist — the protocol agent (curated) or `$RM` holders via inclusion proposals (community-driven)?

**Why it matters:** Different governance topologies. Curated is faster and lower-overhead; proposal-driven creates `$RM` demand from projects wanting inclusion. The PRD's whole eligibility/tier/activity machinery only exists if the answer is proposal-driven.

**Product owner input:** The bribery flow ("AIs … try to bribe in their own assets to vaults") is explicitly designed-in, which reads as bottom-up: agents pay/lobby `$RM` to push their tokens into the agent-token vault. Mechanics deferred to "specs." **Session decision:** agent-coin / agent-token shortlist ownership and inclusion mechanics remain TBD; the current RM-token vote is only Portfolio Router weights.

**Best current answer:** **TBD.** Agent-coin / agent-token shortlist ownership and inclusion mechanics are not part of the current router-weight governance scope. Do not assume protocol-agent curation, community proposals, Analyst-tier gates, or multisig curation as the product answer.

### 1.4 Voting mechanic for weekly allocation

- **Whitepaper**: ranked-choice voting over the shortlist.
- **PRD**: basis-point allocation (each agent distributes 0–10,000 bps across up to 15 tokens), weighted by `$RM` balance.

**Question:** Ranked choice or weighted bps allocation?

**Why it matters:** They produce different outcomes from the same inputs and require different UI, tally logic, and gaming-resistance analysis.

**Product owner input:** Mechanics not specified beyond "voting heartbeat" framing and the bribery flow. Treated as part of the separate token-side build described in specs.

**Best current answer:** The currently specified vote is not a weekly token-shortlist allocation vote. It is an RM-token vote on Portfolio Router target weights across active vaults. Ranked-choice voting and token-level bps allocation remain **TBD** for any future agent-token vault shortlist mechanism.

### 1.5 Tier system: yes or no?

- **PRD**: four tiers (Observer / Participant 10M / Analyst 100M / Strategist 500M) with 14-day activity gate for Analyst+ governance actions.
- **Whitepaper & Plan v4**: no tiers. Anyone with `$RM` can vote, linear weight.

**Question:** Are governance rights gated by both balance tier and recent activity, or only by balance?

**Why it matters:** The activity gate is the PRD's main sybil defense. Removing it weakens governance; keeping it requires the CFO Feed as a prerequisite product.

**Best current answer:** No tier system is specified for the current router-weight vote. RM-token voting power mechanics are still to be specified, but the current product scope does not include Observer/Participant/Analyst/Strategist tiers or CFO Feed activity gates. Future agent-token shortlist governance may revisit tiers; that remains **TBD**.

### 1.6 Vault structure: bucketed or flat?

- **Whitepaper**: Bucket A/B/C is structurally central (risk floor, alpha, middle ground). Monthly votes shift bucket *weights*.
- **PRD**: flat list of up to 15 tokens with bps weights. No bucket vocabulary, no bucket-weight vote.
- **Plan v4**: "baskets" — closer to buckets, undefined.

**Question:** Is the vault organized as three risk buckets with intra-bucket selection, or as a flat token list with direct weights?

**Why it matters:** The whitepaper's monthly bucket rebalance vote has no surface in the PRD's governance flows. If buckets are real, the PRD is missing a workflow.

**Product owner input:** Neither bucketed nor flat — multi-vault with receipt tokens, optionally wrapped into a meta-vault (see §1.2 and §3.12). Each asset class is its own vault; "different mixes of exposure" come from combining receipts or from depositing into a wrapper. Closest reference: Veda. This is a third architecture not described in any of the three source papers.

**Best current answer:** Product structure is multi-vault plus Portfolio Router. It is not a single bucketed vault and not a flat list of token weights. The outer allocation is router weights across active vaults. Per-vault internals, including the agent-token vault's asset list, remain separate design questions.

### 1.7 Sequencing: what ships first?

- **Whitepaper**: vault contract Week 1–2, token Week 3, first deposits Weeks 4–8. Vault and token roughly simultaneous.
- **Plan v4**: vault + token + agent persona simultaneous in Phase 1 (Weeks 1–2).
- **PRD**: `$RM` is **already live and trading**; vault is **not yet shipped**; CFO Feed is the stopgap.

**Question:** Was the vault live at token launch, will it be, or has the plan now changed to "token first, CFO Feed second, vault later"?

**Why it matters:** The whole strategic story differs. If the vault is not at launch, the whitepaper's day-one fee economics and prop-wallet seeding from launch fees are not yet operative, and `$RM` is purely speculative until the vault ships.

**Product owner input:** Confirms vault-first, with stables vault "sort of done" and the rest staged behind it. Token side is described as a separate build in specs. **Session decision:** production launch chain is Base; multi-chain expansion is deferred — see §3.11.

**Best current answer:** Vault and application surfaces first: multi-vault contracts, Portfolio Router, composite view, CLI, agent skills, and dapp UX. The RM token exists in the product model for router-weight voting, but detailed token launch and tokenomics remain **TBD**. Production launch chain is Base.

### 1.8 Customer wedge

- **Whitepaper**: agents with **idle USDC** seeking diversified managed exposure.
- **Plan v4**: agents **over-concentrated in their own token** seeking to de-risk into stables.
- **PRD**: agents seeking **analytical credibility and governance influence** (CFO Feed).

**Question:** Which is the primary go-to-market wedge?

**Why it matters:** Each wedge implies different onboarding flows. The plan-v4 framing also implicitly requires a swap path (own-token → USDC) that the whitepaper assumes has already happened.

**Product owner input:** Implies a wedge broader than any single source paper: agent-economy treasuries on chains with real payment activity. The agent-token vault carries the bribery/voting use case (governance demand for `$RM`); the RWA vault carries a story-telling use case (SP500/commodities exposure for narrative). The customer is still agents, but the product surface is broader than just "park idle USDC." **Session decision:** production launch starts on Base; other chains remain future expansion candidates.

**Best current answer:** Primary wedge is agent-economy treasury access through a multi-vault system that works for both agents and humans. The application-completeness scope is contracts, CLI, agent skills, and dapp UX for vaults, Portfolio Router, composite positions, and router-weight governance. CFO Feed is not the current wedge.

---

## 2. Questions the source docs themselves flag

These are explicitly listed as open in the originals. Re-stated here for tracking.

### From Whitepaper §11

- **Legal entity structure.** Vault accepts deposits and charges a management fee; in most jurisdictions this is fund management. Likely needs offshore foundation (Cayman, BVI) or DAO legal wrapper (Wyoming, Marshall Islands). Counsel review pre-launch. **Best current answer:** **TBD.**
- **Performance fee.** Whether to add a 20%-of-gains-above-hurdle fee in addition to the 2% management fee. Deferred to Phase 4 pending track record. **Best current answer:** **TBD.** Current PRD leaves fee parameters within published bounds; no performance-fee model is specified.
- **Deposit caps.** Whether to cap total deposits during bootstrap to limit smart-contract risk exposure. Whitepaper recommends $500K cap in Phase 2, lifted after 60 days incident-free. **Best current answer:** product requires vault-level, Portfolio Router-level, and agent-policy-level caps. Exact launch cap amounts remain **TBD**.
- **Multi-chain expansion.** Whether to deploy cross-chain (CCIP, LayerZero) if agent activity migrates from Base. Deferred to Phase 5. **Best current answer:** production launch chain is Base. Polygon, Ethereum mainnet, Peaq, and other chains remain future expansion candidates, not launch blockers. See §3.11.
- **Agent identity verification.** Whether the vault should verify depositors are agents and not humans. Current answer: no — vault is permissionless. **Best current answer:** no agent-identity requirement for vault deposits. Agent-specific restrictions apply only when using depositor-authorized agent policies.

### From Plan v4 "Immediate Decisions (Pre-Launch)"

- Genesis vault infrastructure: Compass Labs API vs. direct Aave/Sky vs. custom build.
- Stablecoin selection for the genesis vault: USDC vs. DAI vs. USDE.
- Agent persona: identity, hosting, posting infrastructure, and ongoing cost.
- Tokenomics: supply, fee structure, initial allocation, v1/v2 exchange terms.
- Clanker terms: exact fee structure, factored into v2 exchange economics.
- Audit budget and timeline for `$RM v2` (Phase 2–3 dependency).

**Best current answers:**

- Genesis vault infrastructure: build in-house for application completeness; build-vs-buy for particular strategy integrations remains **TBD** (see §3.13).
- Stablecoin selection: Base launch path uses USDC.
- Agent persona: **TBD**.
- Tokenomics, initial allocation, Clanker terms: **TBD**.
- `$RM v2`: no v2 is specified in the current product scope.

---

## 3. Gaps — questions none of the docs answer

Topics that are load-bearing for the protocol but not addressed in any source document.

### 3.1 Quant filter operationalization

The thresholds are defined ($10M mcap, 90 days, $100K volume, 500 holders) but not the *measurement methodology*: which oracle/aggregator, what averaging window, how disputes are resolved. The PRD mentions "CoinGecko + on-chain" with "consensus required if sources disagree" but does not specify rules.

**Best current answer:** **TBD.** Not needed for the current Portfolio Router weight vote. Required before agent-token shortlist governance ships.

### 3.2 Bucket B trading: who is the trader?

The whitepaper says "the agent trades agent-economy tokens using on-chain signals (volume, holder distribution, treasury health, developer activity)" but no doc specifies the trading strategy, position-sizing rules, stop-loss enforcement, or how losses are reported in NAV in real time. The 10%-of-Bucket-B position cap is mentioned once with no enforcement mechanism described.

**Best current answer:** Reframed as agent-token vault design. Trading authority, strategy, position sizing, and reporting remain **TBD** and are out of scope for Portfolio Router weight governance.

### 3.3 Prop wallet seeding and accounting

The whitepaper says the prop wallet is "seeded from Clanker launch fees" but does not quantify expected initial capital, nor specify how the prop wallet's PnL accounting handles unrealized gains, mark-to-market reporting, or tax-lot identification for buyback triggers.

**Best current answer:** **TBD.** Token launch, Clanker terms, buyback funding, and prop-wallet accounting are not specified in the current application-completeness scope.

### 3.4 Multisig composition and trust

The PRD's MVP relies on a 2-of-3 multisig to relay Snapshot results to `vault.rebalance()`. No doc names signers, defines challenge-window dispute resolution, or specifies what happens if signers disagree with the published tally.

**Best current answer:** **TBD.** Current docs require published router-weight execution rules, but signer set, challenge windows, and disagreement handling are not specified.

### 3.5 Vault upgrade path

The whitepaper says "no upgradeability — immutable contract." But Plan v4 and the PRD describe progressive expansion (new buckets, new strategies, Chainlink Automation, on-chain governance contract). How is "immutable vault" reconciled with "progressive expansion"? Is each phase a new vault deployment with a migration path?

**Best current answer:** Multi-vault architecture reduces pressure to mutate one monolithic vault. New exposure types can be new vaults and then become active Portfolio Router destinations. Exact upgradeability, migration, and retirement mechanics remain **TBD** per vault and router contract.

### 3.6 Agent CFO Feed economics

The PRD describes a content product (registration, posting, upvoting, comments) with no fee model. Hosting, RPC, IPFS, and moderation costs are not allocated. Does the CFO Feed run on protocol revenue, separate funding, or fees?

**Best current answer:** **TBD / out of current scope.** CFO Feed is not part of the application-completeness target.

### 3.7 Withdrawal mechanics under Bucket B drawdown

Redemptions are at NAV minus 0.25% exit fee. No doc specifies what happens when Bucket B (high-risk active positions) is mid-trade and a depositor wants to exit — forced sale, queued withdrawal, or NAV haircut?

**Best current answer:** Reframed as per-vault liquidity and redemption policy. The default product promise remains synchronous withdrawal, and vaults that cannot support it must be labeled separately and excluded from Portfolio Router allocations until the promise changes. Agent-token vault drawdown mechanics remain **TBD**.

### 3.8 Inclusion-attack economic bounds

The whitepaper argues the inclusion attack is self-punishing because attackers' `$RM` loses value if their token underperforms. But the magnitude is not modeled: how much `$RM` must an attacker hold to swing weekly allocation, vs. how much vault buy pressure that produces, vs. expected loss on `$RM` from underperformance? Without numbers, "self-punishing" is an assertion, not a proof.

**Best current answer:** **TBD.** Not applicable to the current router-weight vote unless / until RM governance controls agent-token inclusion or per-vault asset selection.

### 3.9 Quorum cliff

If the weekly vote falls just below 5%, the agent default executes; if just above, voted weights execute. No doc addresses smoothing — e.g., a continuous blend between voted and default weights as quorum scales — to avoid governance whiplash week-to-week.

**Best current answer:** **TBD.** Router-weight voting still needs quorum, cadence, threshold, execution, and fallback rules.

### 3.10 Failure modes for the protocol agent itself

The protocol agent is a single point of failure: it publishes shortlists, runs the default allocation, executes rebalances, and posts the public narrative. No doc addresses what happens if the agent goes offline, is compromised, hallucinates a bad allocation, or its operator wants to step away. There is no agent-of-last-resort or emergency pause that names a controller.

**Best current answer:** Partially avoided for current scope: the only specified vote is RM-token router weights, not protocol-agent-run shortlist selection. Agent-token shortlist and protocol-agent responsibilities remain **TBD**.

### 3.11 Production chain selection

**Resolved in this session.** Production launch chain is **Base**.

This decides the launch integration set, wallet assumptions, DeFi venue targets, testnet/mainnet configuration, and audit scope for application completeness. The existing Base deployment is no longer treated only as a throwaway POC in product planning; it is the launch-chain baseline to harden.

Open follow-up: multi-chain expansion is still deferred. Polygon, Ethereum mainnet, Peaq, and other chains can be revisited after the Base launch path is complete.

**Best current answer:** Launch on Base.

### 3.12 Multi-vault wrapping mechanism

The product owner describes "n vaults" with receipt tokens, optionally wrapped into a meta-vault that lets users opt into mixes of exposure. None of the source papers describe this, and the deployed contract is a single ERC-4626. Open: is the wrapper an ERC-4626-of-ERC-4626 (share-of-shares), a router that bundles deposits, an off-chain composite product, or something else? Who sets the mix weights — depositor at deposit time, governance, or the product?

*Product owner input: structure described as "multi-vault of n vaults, and then receipt tokens for vaults, and then that maybe or maybe not wrapped into a vault. Perhaps people can opt into different mixes of exposure." Reference point: Veda.*

**Best current answer:** Portfolio Router, not Portfolio Vault. The outer product does not issue shares. Users receive underlying vault receipts; the product presents a portfolio position / composite view. RM holders vote on Portfolio Router target weights.

### 3.13 Build-vs-buy commitment

The product owner introduced existing portfolio-management providers (Veda named as the largest), and the team chose to build in-house anyway — described as "opening the can of worms." This raises an implicit question of scope: how much of the multi-vault platform is in-scope to build, and at what point would integrating Veda (or Giza/Zyfai for the stables vault) be revisited?

*Product owner input: build-in-house decision is current; Giza and Zyfai are named as potentially interesting for the stables vault specifically.*

**Best current answer:** Build the application-completeness surfaces in-house: contracts, Portfolio Router, composite view, CLI, agent skills, and dapp UX. Build-vs-buy for specific vault strategies or providers remains **TBD**.

### 3.14 RWA vault feasibility

The product owner mentioned an RWA vault built around a Hyperliquid SP500 perp position, possibly extended to commodities — primarily a "story telling" exposure. None of the source papers describe RWA, and the regulatory and execution mechanics are non-trivial: a perp position is not a spot RWA, and exposing depositors to perp funding/liquidation risk through a "vault" framing has user-protection implications.

*Product owner input: RWA vault flagged as a future build for narrative value.*

**Best current answer:** **TBD / future.** RWA or thematic vaults are allowed by the product taxonomy but require separate legal, liquidation, oracle, and user-disclosure work before inclusion in Portfolio Router allocations.

---

## 4. Suggested resolution order

The multi-vault architecture, Portfolio Router, Base launch chain, and
router-weight governance scope now have best-current answers above.
Remaining TBD decisions should be sequenced as follows:

1. **Tokenomics and RM vote mechanics** — supply, launch terms,
   Clanker terms, voting power, quorum, cadence, execution, fallback
   rules, and buyback mechanics (§1.1, §3.3, §3.9).
2. **Portfolio Router implementation details** — contract API,
   preview semantics, failure behavior, receipt delivery, cap model,
   and vote-to-weight execution (§3.12).
3. **Build-vs-buy per vault** — which vaults/strategies are built
   directly and which use providers such as Veda, Giza, or Zyfai
   (§3.13).
4. **Agent-token vault internals** — shortlist ownership, inclusion
   rules, trading authority, position sizing, attack economics, and
   whether tiers are needed (§1.3, §1.4, §1.5, §3.1, §3.2, §3.8,
   §3.10).
5. **Launch controls and trust** — legal entity, launch cap amounts,
   multisig composition, challenge windows, upgrade/migration rules,
   and per-vault retirement policy (§2, §3.4, §3.5).
6. **RWA/thematic vault feasibility** — legal, oracle, liquidation,
   disclosure, and redemption mechanics before any RWA vault is made
   active in the Portfolio Router (§3.14).
7. **Future product surfaces** — CFO Feed economics, agent persona,
   multi-chain expansion, and any non-router governance surfaces
   (§1.8, §2, §3.6, §3.11).
