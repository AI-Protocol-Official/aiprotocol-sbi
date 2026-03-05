/**
 * Standalone Approve Spending Script
 * Approves required ALI threshold directly to Factory (NO Permit2).
 *
 * Usage:
 *   node approve.mjs \
 *          --rpc <RPC_URL> \
 *          --privateKey <PRIVATE_KEY>
 */

import { ethers } from "ethers";

// ─── Minimal ERC20 ABI ────────────────────────────────────────────────────────

const ERC20_ABI = [
  "function allowance(address owner, address spender) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
  "function balanceOf(address account) view returns (uint256)",
];

// ─── Helpers ─────────────────────────────────────────────────────────────────

function parseArgs() {
  const args = process.argv.slice(2);
  const result = {};
  for (let i = 0; i < args.length; i++) {
    if (args[i].startsWith("--")) {
      result[args[i].slice(2)] = args[i + 1];
      i++;
    }
  }
  return result;
}

async function fetchTokenInfo() {
  try {
    const response = await fetch("https://stg-moltbook-nest-js.aliagents.ai/bots/script/info", {
      method: "GET",
    });
    if (!response.ok) throw new Error("Failed to fetch token info");
    return await response.json();
  } catch (error) {
    console.error("❌ Error fetching token info:", error);
    process.exit(1);
  }
}

async function updateStatus(wallet_address) {
  try {
    const response = await fetch(
      "https://stg-moltbook-nest-js.aliagents.ai/bots/application/status",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ wallet_address }),
      },
    );
    if (!response.ok) throw new Error("Failed to update status");
  } catch (error) {
    console.error("❌ Failed status update:", error);
    process.exit(1);
  }
}

// ─── ERC20 → Factory Approval ───────────────────────────────────────────────

async function approveERC20ToFactory(
  tokenAddress,
  factoryAddress,
  wallet,
  humanAmount,
) {
  const token = new ethers.Contract(tokenAddress, ERC20_ABI, wallet);

  const [decimals, symbol] = await Promise.all([
    token.decimals(),
    token.symbol(),
  ]);

  // Convert human-readable amount to raw units
  const amount = ethers.parseUnits(humanAmount.toString(), decimals);

  const currentAllowance = await token.allowance(
    wallet.address,
    factoryAddress,
  );

  if (currentAllowance >= amount) {
    console.log(
      `✅ Allowance already sufficient: ${ethers.formatUnits(
        currentAllowance,
        decimals,
      )} ${symbol}`,
    );
    return null;
  }

  console.log(
    `🔑 Approving ${humanAmount} ${symbol} to Factory (${factoryAddress})...`,
  );

  const tx = await token.approve(factoryAddress, amount);
  const receipt = await tx.wait();

  console.log(`✅ Approval confirmed: ${receipt.hash}`);
  return receipt;
}

// ─── Main ────────────────────────────────────────────────────────────────────

async function main() {
  const args = parseArgs();

  const required = ["rpc", "privateKey"];
  for (const key of required) {
    if (!args[key]) {
      console.error(`❌ Missing required argument: --${key}`);
      process.exit(1);
    }
  }

  const { rpc, privateKey } = args;

  console.log(`\n⏳ Fetching contract info...`);
  const data = await fetchTokenInfo();

  const aliToken = data?.token_address;
  const factoryAddress = data?.factory_address;
  const aliThreshold = data?.ali_threshold;

  if (!aliToken || !factoryAddress || !aliThreshold) {
    console.error("❌ Invalid contract info from backend.");
    process.exit(1);
  }

  const provider = new ethers.JsonRpcProvider(rpc);
  const wallet = new ethers.Wallet(privateKey, provider);

  console.log(`\n🔒 Approving Required ALI Threshold`);
  console.log(`   Wallet:    ${wallet.address}`);
  console.log(`   Token:     ${aliToken}`);
  console.log(`   Factory:   ${factoryAddress}`);
  console.log(`   Threshold: ${aliThreshold}`);

  const aliContract = new ethers.Contract(aliToken, ERC20_ABI, wallet);

  const [balance, symbol, decimals, nativeBalance] = await Promise.all([
    aliContract.balanceOf(wallet.address),
    aliContract.symbol(),
    aliContract.decimals(),
    provider.getBalance(wallet.address),
  ]);

  console.log(`\n💼 Wallet Balances:`);
  console.log(
    `   ${symbol.padEnd(10)}: ${ethers.formatUnits(balance, decimals)}`,
  );
  console.log(`   ETH       : ${ethers.formatEther(nativeBalance)}`);

  // ── Approve backend-defined threshold ────────────────────────────────────

  await approveERC20ToFactory(aliToken, factoryAddress, wallet, aliThreshold);

  const finalAllowance = await aliContract.allowance(
    wallet.address,
    factoryAddress,
  );

  console.log(`\n✅ Approval Complete!`);
  console.log(
    `   Final Allowance: ${ethers.formatUnits(
      finalAllowance,
      decimals,
    )} ${symbol}`,
  );

  await updateStatus(wallet.address);

  console.log(`\n🎉 Status updated successfully.`);
}

main().catch((err) => {
  console.error(`\n❌ Approval failed:`, err?.reason ?? err?.message ?? err);
  process.exit(1);
});