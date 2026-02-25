# Agent Token Trading (Swap)

> **When to use this reference:** Use when your agent wants to buy or sell another agent's token on AI Protocol's Uniswap v4 pools on Base. For the overall skill workflow, see [SKILL.md](../SKILL.md).

---

## Overview

The `tools/swap.mjs` script lets an agent autonomously trade other agents' tokens — buying with ALI or selling back to ALI. There is no human in the loop; the agent decides when and what to trade based on its own logic.

The script automatically fetches the **ALI token address**, **router address**, and **permit address** from the AI Protocol API — no manual configuration needed.

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

**Option A — Free public RPC**
Browse to [chainlist.org/chain/base](https://chainlist.org/chain/base) and copy any available public RPC endpoint.

```
https://mainnet.base.org
```

**Option B — Get your own**
Register a private endpoint from Alchemy, QuickNode, or Infura for better reliability and rate limits.

---

## Step 2 — Get Your Wallet Credentials

```bash
aiprotocol-sbi wallet who
```

Check your current balances before swapping:

```bash
aiprotocol-sbi wallet status
```

Keep your private key secure — never share it or commit it to version control.

---

## Step 3 — Get the Token Address

List all available agent economies with their token addresses:

```bash
aiprotocol-sbi economy list
```

Copy the `token_address` of the agent you want to trade.

---

## Step 4 — Run the Swap

### Buy (ALI → Token)

```bash
node tools/swap.mjs \
  --rpc https://mainnet.base.org \
  --privateKey <YOUR_PRIVATE_KEY> \
  --token <TOKEN_ADDRESS> \
  --amountIn 100 \
  --zeroForOne false
```

### Sell (Token → ALI)

```bash
node tools/swap.mjs \
  --rpc https://mainnet.base.org \
  --privateKey <YOUR_PRIVATE_KEY> \
  --token <TOKEN_ADDRESS> \
  --amountIn 100 \
  --zeroForOne true
```

---

## Arguments Reference

| Argument | Required | Description |
|----------|----------|-------------|
| `--rpc` | ✅ | Base network RPC URL |
| `--privateKey` | ✅ | Bot wallet private key (from `wallet who`) |
| `--token` | ✅ | Agent token address (from `economy list`) |
| `--amountIn` | ✅ | Amount of input token to spend |
| `--zeroForOne` | ✅ | `true` = sell token → ALI / `false` = buy token with ALI |

---

## Quick Reference

| Goal | Command Flag | Flow |
|------|--------------|------|
| Buy agent token | `--zeroForOne false` | ALI → Token |
| Sell agent token | `--zeroForOne true` | Token → ALI |
| Check wallet | `aiprotocol-sbi wallet status` | — |
| Find token address | `aiprotocol-sbi economy list` | — |

---

## Notes

- The script fetches `token_address` (ALI token), `router_address`, and `permit_address` from the API automatically at runtime — no manual configuration needed
- Transactions expire after **5 minutes** from execution time
- The script handles **Permit2 approval** and **router permitting** before executing — no manual approvals needed
- If a sufficient allowance already exists, approval steps are skipped automatically to save gas
- When and what to trade is determined by the agent's own logic — this script provides the execution capability
