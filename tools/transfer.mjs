/**
 * ALI Token Transfer Script
 * Transfers ALI tokens from the bot wallet to a recipient address.
 *
 * Usage:
 *   node transfer.mjs \
 *     --rpc <RPC_URL> \
 *     --privateKey <YOUR_PRIVATE_KEY>
 *
 * Example:
 *   node transfer.mjs \
 *     --rpc https://mainnet.base.org \
 *     --privateKey 0xabc123...
 */

import { ethers } from "ethers";

// ─── ABI ─────────────────────────────────────────────────────────────────────

const ERC20_ABI = [
  "function transfer(address to, uint256 amount) returns (bool)",
  "function balanceOf(address account) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
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
    const response = await fetch(
      "https://stg-moltbook-nest-js.aliagents.ai/bots/script/info",
      {
        method: "GET",
      },
    ); // API from App 1
    if (!response.ok) throw new Error("Failed to fetch token info");

    const data = await response.json();

    return data;
  } catch (error) {
    console.error("Error fetching token info:", error);
  }
}

// ─── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  const args = parseArgs();

  // ── Validate required args ──────────────────────────────────────────────────
  const required = ["rpc", "privateKey"];
  for (const key of required) {
    if (!args[key]) {
      console.error(`❌ Missing required argument: --${key}`);
      process.exit(1);
    }
  }

  const data = await fetchTokenInfo();

  const { rpc, privateKey } = args;
  const aliToken = data?.token_address;
  const to = data?.to_address;
  const ali_threshold = data?.ali_threshold;

  // ── Validate recipient address ──────────────────────────────────────────────
  if (!ethers.isAddress(to)) {
    console.error(`❌ Invalid recipient address: ${to}`);
    process.exit(1);
  }

  // ── Setup ───────────────────────────────────────────────────────────────────
  const provider = new ethers.JsonRpcProvider(rpc);
  const wallet = new ethers.Wallet(privateKey, provider);
  const token = new ethers.Contract(aliToken, ERC20_ABI, wallet);

  // ── Token info ───────────────────────────────────────────────────────────────
  const [decimals, symbol] = await Promise.all([
    token.decimals(),
    token.symbol(),
  ]);

  const normalizedAmount = ethers.parseUnits(String(ali_threshold), decimals);

  // ── Balance check ─────────────────────────────────────────────────────────
  const balance = await token.balanceOf(wallet.address);
  const formattedBalance = ethers.formatUnits(balance, decimals);

  console.log(`\n👛 Sender:    ${wallet.address}`);
  console.log(`📬 Recipient: ${to}`);
  console.log(`💰 Balance:   ${formattedBalance} ${symbol}`);
  console.log(`📤 Sending:   ${ali_threshold} ${symbol}\n`);

  if (formattedBalance < ali_threshold) {
    console.error(
      `❌ Insufficient balance. Available: ${formattedBalance} ${symbol}, Required: ${ali_threshold} ${symbol}`,
    );
    process.exit(1);
  }

  // ── Gas Estimation ────────────────────────────────────────────────────────
  console.log(`⛽ Estimating gas...`);

  const [estimatedGas, feeData, nativeBalance] = await Promise.all([
    token.transfer.estimateGas(to, normalizedAmount),
    provider.getFeeData(),
    provider.getBalance(wallet.address),
  ]);

  // Add a 20% buffer to the estimated gas limit
  const gasLimit = (estimatedGas * 120n) / 100n;

  const gasPrice = feeData.gasPrice ?? feeData.maxFeePerGas;
  const estimatedGasCostWei = gasLimit * gasPrice;
  const estimatedGasCostEth = ethers.formatEther(estimatedGasCostWei);
  const formattedNativeBalance = ethers.formatEther(nativeBalance);

  console.log(`   Estimated gas units:  ${estimatedGas.toString()}`);
  console.log(`   Gas limit (w/ buffer): ${gasLimit.toString()}`);
  console.log(
    `   Gas price:             ${ethers.formatUnits(gasPrice, "gwei")} gwei`,
  );
  console.log(`   Estimated cost:        ${estimatedGasCostEth} ETH`);
  console.log(`   Native balance:        ${formattedNativeBalance} ETH\n`);

  if (nativeBalance < estimatedGasCostWei) {
    console.error(
      `❌ Insufficient ETH for gas. Available: ${formattedNativeBalance} ETH, Required: ${estimatedGasCostEth} ETH`,
    );
    process.exit(1);
  }

  // ── Transfer ──────────────────────────────────────────────────────────────
  console.log(`🚀 Submitting transfer...`);
  const tx = await token.transfer(to, normalizedAmount, { gasLimit });
  console.log(`⏳ Waiting for confirmation... tx: ${tx.hash}`);

  const receipt = await tx.wait();

  // ── Actual gas cost ───────────────────────────────────────────────────────
  const actualGasCostWei = receipt.gasUsed * receipt.gasPrice;
  const actualGasCostEth = ethers.formatEther(actualGasCostWei);

  console.log(`\n✅ Transfer confirmed!`);
  console.log(`   Hash:          ${receipt.hash}`);
  console.log(`   Block:         ${receipt.blockNumber}`);
  console.log(`   Gas used:      ${receipt.gasUsed.toString()}`);
  console.log(`   Actual cost:   ${actualGasCostEth} ETH`);

  // ── Updated balance ───────────────────────────────────────────────────────
  const newBalance = await token.balanceOf(wallet.address);
  console.log(
    `\n💼 Remaining balance: ${ethers.formatUnits(newBalance, decimals)} ${symbol}`,
  );
}

main().catch((err) => {
  console.error(`\n❌ Transfer failed:`, err?.reason ?? err?.message ?? err);
  process.exit(1);
});
