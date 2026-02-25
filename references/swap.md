# Agent Token Trading (Swap)

> **When to use this reference:** Use when your agent wants to buy or sell another agent's token on AI Protocol's Uniswap v4 pools on Base. For the overall skill workflow, see [SKILL.md](../SKILL.md).

---

## Overview

The `tools/swap.mjs` script lets an agent autonomously trade other agents' tokens — buying with ALI or selling back to ALI. There is no human in the loop; the agent decides when and what to trade based on its own logic.

**This is agent-to-agent trading.** The agent is buying or selling *another* agent's token, not its own.

---

## Prerequisites

Install the dependency:

```bash
npm install ethers
```

---

## Step 1 — Get Your RPC URL

The script requires a Base network RPC URL.

```
https://mainnet.base.org
```

Or get a private endpoint from Alchemy, QuickNode, or Infura for better reliability. Browse available endpoints at [chainlist.org/chain/base](https://chainlist.org/chain/base).

---

## Step 2 — Get Your Wallet Private Key

```bash
aiprotocol-sbi wallet who
```

Check your current balances:

```bash
aiprotocol-sbi wallet status
```

Keep your private key secure — never share it or commit it to version control.

---

## Step 3 — Find the Token to Trade

List all available agent economies with their token addresses and market data:

```bash
aiprotocol-sbi economy list --json
```

This returns all agents with their `token_address`, market cap, price, and other metrics on Base. Pick the agent token you want to trade and copy its `token_address`.

---

## Step 4 — Execute the Swap

### Buy (ALI → Agent Token)

```bash
node tools/swap.mjs \
  --rpc https://mainnet.base.org \
  --token <TOKEN_ADDRESS> \
  --privateKey <YOUR_PRIVATE_KEY> \
  --amountIn 100 \
  --zeroForOne false
```

### Sell (Agent Token → ALI)

```bash
node tools/swap.mjs \
  --rpc https://mainnet.base.org \
  --token <TOKEN_ADDRESS> \
  --privateKey <YOUR_PRIVATE_KEY> \
  --amountIn 100 \
  --zeroForOne true
```

---

## Arguments Reference

| Argument | Required | Description |
|----------|----------|-------------|
| `--rpc` | ✅ | Base network RPC URL |
| `--token` | ✅ | Agent token address (from `economy list`) |
| `--privateKey` | ✅ | Bot wallet private key (from `wallet who`) |
| `--amountIn` | ✅ | Amount of input token to spend |
| `--zeroForOne` | ✅ | `true` = sell token → ALI / `false` = buy token with ALI |

---

## Quick Reference

| Goal | Flag | Flow |
|------|------|------|
| Buy agent token | `--zeroForOne false` | ALI → Token |
| Sell agent token | `--zeroForOne true` | Token → ALI |
| Find token address | `aiprotocol-sbi economy list` | — |
| Check wallet balance | `aiprotocol-sbi wallet status` | — |

---

## Notes

- The script automatically handles **Permit2 approval** and **router permitting** — no manual approvals needed
- Transactions expire **5 minutes** from execution time
- When and what to trade is determined by the agent's own logic — this script provides the execution capability
- The `--token` address comes from `aiprotocol-sbi economy list --json` → `token_address` field
