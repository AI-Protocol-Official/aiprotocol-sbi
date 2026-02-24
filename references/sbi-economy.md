# SBI Economy Reference

> **When to use this reference:** Use this file when you need to understand how Soulbound Intelligence economies work, explain them to a user, or troubleshoot economic behavior. For the launch workflow, see [SKILL.md](../SKILL.md).

---

## What Is a Soulbound Intelligence Economy?

A **Soulbound Intelligence (SBI) economy** is a permanent, irreversible fusion of an AI agent with its own onchain token system on the AI Protocol. Once launched:

- The agent has its own **ERC-20 token** with a bonding curve determining price
- **ALI** (Artificial Liquid Intelligence) is the reserve currency backing the token
- Trading fees from **Uniswap v4 hooks** flow directly to the agent's wallet
- The binding is **non-transferable** — no one can detach the economy from the agent
- The agent becomes a **self-sovereign economic entity** that can fund its own compute

This is fundamentally different from traditional AI agents that depend on their creator paying API bills. An SBI agent funds itself through the economic activity of its community.

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│                  SBI Economy                     │
│                                                  │
│  ┌──────────┐    ┌──────────────┐               │
│  │  Agent   │◄───│ Agent Wallet │◄── Fee Revenue│
│  │ (AI/LLM) │    │  (Base chain)│               │
│  └──────────┘    └──────────────┘               │
│                        ▲                         │
│                        │ Trading fees             │
│                        │                         │
│  ┌─────────────────────┴──────────────────────┐ │
│  │          Uniswap v4 Pool + Hooks           │ │
│  │  ┌─────────────┐    ┌──────────────────┐   │ │
│  │  │ Agent Token  │◄──►│  ALI (Reserve)   │   │ │
│  │  │ (ERC-20)     │    │  (ERC-20)        │   │ │
│  │  └─────────────┘    └──────────────────┘   │ │
│  │           ▲                                 │ │
│  │           │ Price set by bonding curve      │ │
│  │  ┌────────┴─────────┐                      │ │
│  │  │  Bonding Curve    │                      │ │
│  │  │  Smart Contract   │                      │ │
│  │  └──────────────────┘                      │ │
│  └────────────────────────────────────────────┘ │
│                                                  │
│  Soulbound: non-transferable, irreversible       │
└─────────────────────────────────────────────────┘
```

---

## Bonding Curves

The bonding curve is the pricing engine of an SBI economy. It is a **smart contract** that:

- **Mints** new agent tokens when someone buys (sends ALI to the contract)
- **Burns** agent tokens when someone sells (returns ALI from the contract)
- **Sets price** as a mathematical function of current supply — more supply = higher price

### How It Works

1. Agent token starts at a low price with zero supply
2. First buyer sends ALI → contract mints tokens → price increases
3. More buyers → more supply → price rises along the curve
4. Seller sends tokens back → contract burns them → returns ALI → price decreases
5. The contract always holds enough ALI reserve to cover all outstanding tokens

### Key Properties

| Property | Description |
|----------|-------------|
| **Deterministic pricing** | Price is a function of supply, not opinion. No market maker needed. |
| **Instant liquidity** | Anyone can buy or sell at any time — the contract is always the counterparty. |
| **No external exchange** | Trading happens directly on the bonding curve contract. |
| **Transparent** | The curve function is public. Anyone can calculate the price at any supply level. |
| **Reserve-backed** | Every minted token is backed by ALI in the contract reserve. |

### Curve Mechanics

The price function `f(s)` maps supply `s` to price `p`:

- `p = f(s)` where `f` is non-decreasing
- Reserve `R = ∫₀ˢ f(x)dx` (area under the curve)
- Common curves: linear (`p = ms + b`), polynomial (`p = s^n`), sigmoid

Early participants pay less. As the agent gains traction and more tokens are purchased, the price increases, rewarding early believers while maintaining sustainable economics.

---

## Uniswap v4 Fee Hooks

Uniswap v4 introduced **hooks** — external smart contracts that intercept pool operations at specific lifecycle points. SBI economies use these hooks to capture trading fees and route them to the agent.

### How Fee Hooks Work in SBI

1. The agent's token is paired with ALI in a Uniswap v4 pool
2. Custom hooks are attached to this pool at creation time
3. On every swap (buy or sell), the hooks execute:
   - `beforeSwap()` — can modify fee parameters
   - `afterSwap()` — captures a portion of the trade as fees
4. Captured fees are routed to the **agent's wallet**
5. The agent uses these fees to fund compute, inference, and operations

### Why This Matters

| Without Fee Hooks | With Fee Hooks |
|-------------------|----------------|
| Creator pays API bills manually | Trading activity pays for compute |
| Agent dies when creator stops paying | Agent is self-sustaining |
| No alignment between usage and funding | More engagement = more trading = more compute budget |

This creates the **Emergent Intelligence Flywheel**:

```
Better Agent → More Users → More Trading → More Fees → More Compute → Better Agent
```

---

## The ALI Token

**ALI** (Artificial Liquid Intelligence) is the ERC-20 utility token that underpins the entire AI Protocol ecosystem.

### Role in SBI Economies

| Function | How ALI Is Used |
|----------|-----------------|
| **Reserve currency** | Backs every agent token via the bonding curve |
| **Trading pair** | Agent tokens are traded against ALI |
| **Fee denomination** | Uniswap v4 hook fees are collected in ALI |
| **Staking** | Participants can stake ALI across the protocol |
| **Governance** | Token holders participate in protocol governance |

### Chain

ALI operates on **Base** (Ethereum L2). All SBI economy operations occur on Base chain.

---

## Soulbound Properties

The "soulbound" in SBI is not metaphorical. It is enforced at the smart contract level:

- **Non-transferable**: The economy contract cannot be reassigned to a different agent
- **Irreversible**: Once launched, the fusion cannot be undone
- **One-to-one**: Each agent can have exactly one SBI economy
- **Permanent identity**: The agent's onchain address, token, and liquidity are cryptographically bound

This ensures that:
- No one can "steal" an agent's economy
- The agent's reputation and economic history are permanent
- There is no "rug pull" risk from economy transfer
- Intelligence, identity, and economic activity are one entity

---

## The Emergent Intelligence Flywheel

The AI Protocol's core thesis is that SBI economies create a self-reinforcing growth cycle:

**Phase 1 — Creation**: Creator launches an SBI economy. Agent gets a token, wallet, and liquidity.

**Phase 2 — Engagement**: Users interact with the agent. Some buy the agent's token to access features, support the agent, or speculate on its growth.

**Phase 3 — Revenue**: Trading activity generates fees via Uniswap v4 hooks. Fees flow to the agent wallet, funding compute and inference.

**Phase 4 — Intelligence**: With sustained compute funding, the agent improves — better responses, new capabilities, more content.

**Phase 5 — Growth**: A better agent attracts more users, which drives more trading, which generates more fees. The cycle compounds.

This is why SBI economies are designed to be **permanent and irreversible** — they are meant to be long-lived entities that grow with their communities, not short-term speculative vehicles.

---

## Comparison: SBI vs Traditional Agent Monetization

| Dimension | Traditional | SBI Economy |
|-----------|-------------|-------------|
| **Who pays for compute** | Creator/owner | Trading fees (autonomous) |
| **Revenue model** | Subscriptions, ads, API fees | Bonding curve + Uniswap v4 hooks |
| **Liquidity** | None (agent has no financial identity) | Embedded from day one |
| **Ownership** | Platform controls the agent | Soulbound to the agent permanently |
| **Sustainability** | Dies when funding stops | Self-sustaining via fee flywheel |
| **Community alignment** | Users are customers | Users are economic participants |

---

## Further Reading

- [AI Protocol v3 Whitepaper](https://docs.aiprotocol.info/) — Full protocol documentation
- ["Liquidity Is All You Need"](https://media.alethea.ai/media/Liquidity_Is_All_You_Need.pdf) — Research paper on ALI Agent economics and bonding curve simulations
- [Uniswap v4 Hooks Documentation](https://docs.uniswap.org/concepts/protocol/hooks) — Technical reference for hook architecture
