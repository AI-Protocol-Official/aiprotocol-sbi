/**
 * Standalone Uniswap v4 Swap Script
 * ALI token, router, and permit addresses are fetched from the API automatically.
 *
 * Usage:
 *   node swap.mjs --rpc <RPC_URL> --token <TOKEN_ADDRESS> --privateKey <PRIVATE_KEY> \
 *                 --amountIn <AMOUNT> --zeroForOne <true|false>
 *
 *  --zeroForOne true  → SELL  (token → ALI)
 *  --zeroForOne false → BUY   (ALI → token)
 */

import { ethers } from "ethers";

// ─── Minimal ABIs ────────────────────────────────────────────────────────────

const ERC20_ABI = [
  "function allowance(address owner, address spender) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function decimals() view returns (uint8)",
  "function balanceOf(address account) view returns (uint256)",
];

const PERMIT2_ABI = [
  "function approve(address token, address spender, uint160 amount, uint48 expiration) external",
  "function allowance(address owner, address token, address spender) view returns (uint160 amount, uint48 expiration, uint48 nonce)",
];

const ROUTER_ABI = [
  "function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable returns (bytes[] memory outputs)",
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

//  * 1 Request Per 10 Seconds
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

function encodeSwapSingleParams({
  poolKey,
  zeroForOne,
  amountSpecified,
  oppositeBound,
  hookData,
}) {
  const abiCoder = new ethers.AbiCoder();
  return abiCoder.encode(
    [
      "tuple(tuple(address currency0,address currency1,uint24 fee,int24 tickSpacing,address hooks) poolKey,bool zeroForOne,uint128 amountSpecified,uint128 oppositeBound,bytes hookData)",
    ],
    [
      [
        [
          poolKey.currency0,
          poolKey.currency1,
          poolKey.fee,
          poolKey.tickSpacing,
          poolKey.hooks,
        ],
        zeroForOne,
        amountSpecified,
        oppositeBound,
        hookData,
      ],
    ],
  );
}

function encodeCurrencyValue({ currency, value }) {
  const abiCoder = new ethers.AbiCoder();
  return abiCoder.encode(["address", "uint256"], [currency, BigInt(value)]);
}

function encodeSwap(poolKey, zeroForOne, amountIn) {
  const payload0 = encodeSwapSingleParams({
    poolKey,
    zeroForOne,
    amountSpecified: amountIn,
    oppositeBound: "0",
    hookData: "0x0000000000000000000000000000000000000000",
  });

  const payload1 = encodeCurrencyValue({
    currency: zeroForOne ? poolKey.currency0 : poolKey.currency1,
    value: amountIn.toString(),
  });

  const payload2 = encodeCurrencyValue({
    currency: zeroForOne ? poolKey.currency1 : poolKey.currency0,
    value: "0",
  });

  const actions = "0x060c0f";
  const abiCoder = new ethers.AbiCoder();
  return abiCoder.encode(
    ["bytes", "bytes[]"],
    [actions, [payload0, payload1, payload2]],
  );
}

async function approveToken(tokenAddress, amount, permitAddress, wallet) {
  const token = new ethers.Contract(tokenAddress, ERC20_ABI, wallet);
  const currentAllowance = await token.allowance(wallet.address, permitAddress);

  if (currentAllowance >= amount) {
    console.log(`✅ Allowance already sufficient: ${currentAllowance}`);
    return null;
  }

  console.log(`🔑 Approving ${amount} of ${tokenAddress} to Permit2...`);
  const tx = await token.approve(permitAddress, amount);
  const receipt = await tx.wait();
  console.log(`✅ Approval confirmed: ${receipt.hash}`);
  return receipt;
}

async function permitTokenToRouter(
  tokenAddress,
  amount,
  deadline,
  permit2,
  routerAddress,
) {
  console.log(
    `🔑 Permitting ${amount} of ${tokenAddress} to Router ${routerAddress}`,
  );

  const tx = await permit2.approve(
    tokenAddress,
    routerAddress,
    amount,
    deadline,
  );
  const receipt = await tx.wait();
  console.log(`✅ Permit confirmed: ${receipt.hash}`);
  return receipt;
}

// ─── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  const args = parseArgs();

  // ── Validate required args ──────────────────────────────────────────────────
  const required = ["rpc", "token", "privateKey", "amountIn", "zeroForOne"];
  for (const key of required) {
    if (!args[key]) {
      console.error(`❌ Missing required argument: --${key}`);
      process.exit(1);
    }
  }

  const { rpc, token, privateKey, amountIn } = args;

  const data = await fetchTokenInfo();

  const zeroForOne = args.zeroForOne === "true";
  const TOKEN_DECIMALS = Number(args.decimals ?? 18);
  const aliToken = data?.token_address;
  const routerAddress = data?.router_address;
  const permitAddress = data?.permit_address;
  console.log(
    `\n🔄 Swap Direction: ${zeroForOne ? "🔴 SELL (token → ALI)" : "🟢 BUY (ALI → token)"}`,
  );
  console.log(`   Token:      ${token}`);
  console.log(`   ALI Token:  ${aliToken}`);
  console.log(`   Amount In:  ${amountIn}`);

  // ── Setup ───────────────────────────────────────────────────────────────────
  const provider = new ethers.JsonRpcProvider(rpc);
  const wallet = new ethers.Wallet(privateKey, provider);

  console.log(`👛 Wallet: ${wallet?.address}`);

  // ── Normalise amounts ───────────────────────────────────────────────────────
  const normalizedAmountIn = ethers.parseUnits(
    String(amountIn),
    TOKEN_DECIMALS,
  );
  // ── Pool key ─────────────────────────────────────────────────────────────────
  const aliLower = aliToken?.toLowerCase();
  const tokenLower = token?.toLowerCase();
  const aliIsZero = aliLower < tokenLower;

  const poolKey = {
    currency0: aliIsZero ? aliToken : token,
    currency1: aliIsZero ? token : aliToken,
    fee: 5000,
    tickSpacing: 100,
    hooks: "0x0000000000000000000000000000000000000000",
  };

  console.log(
    `🏊 Pool: currency0=${poolKey.currency0}  currency1=${poolKey.currency1}`,
  );

  // ── Contract instances ───────────────────────────────────────────────────────
  const permit2 = new ethers.Contract(permitAddress, PERMIT2_ABI, wallet);
  const router = new ethers.Contract(routerAddress, ROUTER_ABI, wallet);

  const deadline = Math.floor(Date.now() / 1000) + 300; // 5 minutes

  // ── Token to approve: the input token ───────────────────────────────────────
  // zeroForOne=true  → selling token (user gives `token`, receives ALI)
  // zeroForOne=false → buying  token (user gives `aliToken`, receives `token`)
  const inputToken = zeroForOne ? token : aliToken;

  // 1. Approve Permit2 to spend the input token
  await approveToken(inputToken, normalizedAmountIn, permitAddress, wallet);

  // 2. Permit router via Permit2
  await permitTokenToRouter(
    inputToken,
    normalizedAmountIn,
    deadline,
    permit2,
    routerAddress,
  );

  // 3. Encode and execute swap
  const payload = encodeSwap(
    poolKey,
    zeroForOne,
    normalizedAmountIn,
  );

  console.log(`\n🚀 Submitting swap transaction...`);
  const tx = await router.execute("0x10", [payload], deadline, {});
  console.log(`⏳ Waiting for confirmation... tx: ${tx.hash}`);
  const receipt = await tx.wait();

  console.log(`\n✅ Swap confirmed!`);
  console.log(`   Hash:        ${receipt.hash}`);
  console.log(`   Block:       ${receipt.blockNumber}`);
  console.log(`   Gas used:    ${receipt.gasUsed.toString()}`);

  return receipt;
}

main().catch((err) => {
  console.error(`\n❌ Swap failed:`, err?.reason ?? err?.message ?? err);
  process.exit(1);
});
