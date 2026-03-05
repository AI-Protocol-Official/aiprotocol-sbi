/**
 * Standalone Uniswap v4 Swap Script
 * Usage:
 *   node swap.mjs \
 *          --rpc <RPC_URL> \
 *          --token <TOKEN_ADDRESS> \
 *          --privateKey <PRIVATE_KEY> \
 *          --amountIn <TOKEN_SPENDING> \
 *          --type <BUY|SELL>
 *
 *  --type SELL  → SELL  (token → ALI)
 *  --type BUY → BUY   (ALI → token)
 */

import { ethers } from "ethers";

// ─── Minimal ABIs ────────────────────────────────────────────────────────────

const ERC20_ABI = [
  "function allowance(address owner, address spender) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
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

function encodeSwap(poolKey, zeroForOne, amountIn, amountOutMin) {
  const payload0 = encodeSwapSingleParams({
    poolKey,
    zeroForOne,
    amountSpecified: amountIn,
    oppositeBound: amountOutMin,
    hookData: poolKey?.hooks,
  });

  const payload1 = encodeCurrencyValue({
    currency: zeroForOne ? poolKey.currency0 : poolKey.currency1,
    value: amountIn.toString(),
  });

  const payload2 = encodeCurrencyValue({
    currency: zeroForOne ? poolKey.currency1 : poolKey.currency0,
    value: amountOutMin.toString(),
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

  // if (currentAllowance >= amount) {
  //   console.log(`✅ Allowance already sufficient: ${currentAllowance}`);
  //   return null;
  // }

  console.log(`🔑 Approving ${amount} of ${tokenAddress} to Permit2...`);
  const tx = await token.approve(permitAddress, amount);
  const receipt = await tx.wait();
  console.log(`✅ Approval confirmed: ${receipt.hash}`);
  return receipt;
}

async function permitTokenToRouter(
  tokenAddress,
  amount,
  permitExpiration,
  permit2,
  routerAddress,
) {
  // Check existing Permit2 allowance before issuing a new permit.
  // Use BigInt for all comparisons — ethers v6 returns uint160/uint48 as BigInt.
  const ownerAddress = await permit2.runner.getAddress();
  const nowSec = BigInt(Math.floor(Date.now() / 1000));

  try {
    const [currentAmount, currentExpiration] = await permit2.allowance(
      ownerAddress,
      tokenAddress,
      routerAddress,
    );

    if (currentAmount >= amount && currentExpiration > nowSec + 60n) {
      console.log(
        `✅ Permit2 allowance already valid — amount: ${currentAmount}, expires: ${currentExpiration}`,
      );
      return null;
    }
  } catch (err) {
    // If the read fails for any reason, fall through and re-permit
    console.warn(`⚠️  Could not read Permit2 allowance: ${err.message}`);
  }

  console.log(
    `🔑 Permitting ${amount} of ${tokenAddress} to Router ${routerAddress}`,
  );

  const tx = await permit2.approve(
    tokenAddress,
    routerAddress,
    amount,
    permitExpiration,
  );
  const receipt = await tx.wait();
  console.log(`✅ Permit confirmed: ${receipt.hash}`);
  return receipt;
}

// ─── Simulation ──────────────────────────────────────────────────────────────

async function simulateSwap(router, payload, deadline, wallet) {
  console.log(`🧪 Simulating swap...`);

  // Use provider.call directly so we get the raw response instead of
  // ethers trying to ABI-decode bytes[] and throwing BAD_DATA on empty returns.
  const callData = router.interface.encodeFunctionData("execute", [
    "0x10",
    [payload],
    deadline,
  ]);

  try {
    const rawResult = await router.runner.provider.call({
      to: await router.getAddress(),
      from: wallet.address,
      data: callData,
    });

    // rawResult === "0x" means the router returned nothing — this is normal
    // for Uniswap v4 Universal Router on some chains; treat it as success.
    if (!rawResult || rawResult === "0x") {
      console.log(
        `✅ Simulation passed — router returned empty (expected for this router)`,
      );
      return true;
    }

    // Attempt to decode the returned bytes[] for informational output
    try {
      const abiCoder = new ethers.AbiCoder();
      const [outputs] = abiCoder.decode(["bytes[]"], rawResult);
      if (outputs && outputs.length > 0) {
        const decoded = outputs.map((o) => {
          try {
            const [amount] = abiCoder.decode(["uint256"], o);
            return amount.toString();
          } catch {
            return o;
          }
        });
        console.log(
          `✅ Simulation passed — simulated output amounts: ${decoded.join(", ")}`,
        );
      } else {
        console.log(`✅ Simulation passed — swap is expected to succeed`);
      }
    } catch {
      console.log(`✅ Simulation passed — swap is expected to succeed`);
    }

    return true;
  } catch (err) {
    // provider.call throws when the call reverts — this is a real failure
    const reason =
      err?.revert?.args?.[0] ??
      err?.reason ??
      err?.error?.message ??
      err?.message ??
      "Unknown revert reason";

    // Filter out BAD_DATA decode errors — these are ethers post-processing
    // issues, not actual reverts from the contract
    if (err?.code === "BAD_DATA") {
      console.log(
        `✅ Simulation passed — router returned non-standard data (not a revert)`,
      );
      return true;
    }

    console.error(`❌ Simulation failed — swap would revert`);
    console.error(`   Reason: ${reason}`);
    return false;
  }
}

// ─── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  const args = parseArgs();

  // ── Validate required args ──────────────────────────────────────────────────
  const required = ["rpc", "token", "privateKey", "amountIn", "type"];
  for (const key of required) {
    if (!args[key]) {
      console.error(`❌ Missing required argument: --${key}`);
      process.exit(1);
    }
  }

  const { rpc, token, privateKey, amountIn } = args;

  const data = await fetchTokenInfo();

  const is_buy = args?.type === "BUY";
  const TOKEN_DECIMALS = data?.decimals;
  const aliToken = data?.token_address;
  const routerAddress = data?.router_address;
  const permitAddress = data?.permit_address;
  const fee = data?.fee;
  const tick_spacing = data?.tick_spacing;
  const hook_data = data?.hook_data;

  console.log(
    `\n🔄 Swap Direction: ${!is_buy ? "🔴 SELL (token → ALI)" : "🟢 BUY (ALI → token)"}`,
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
  const amountOutMinBigInt = "0";

  // ── Pool key ─────────────────────────────────────────────────────────────────
  const aliLower = aliToken?.toLowerCase();
  const tokenLower = token?.toLowerCase();
  const aliIsZero = aliLower < tokenLower;

  const zeroForOne = is_buy
    ? aliIsZero
      ? true
      : false
    : aliIsZero
      ? false
      : true;

  const poolKey = {
    currency0: aliIsZero ? aliToken : token,
    currency1: aliIsZero ? token : aliToken,
    fee,
    tickSpacing: tick_spacing,
    hooks: hook_data,
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
  const inputToken = is_buy ? aliToken : token;
  const outputToken = is_buy ? token : aliToken;
  const inputTokenContract = new ethers.Contract(inputToken, ERC20_ABI, wallet);
  const outputTokenContract = new ethers.Contract(
    outputToken,
    ERC20_ABI,
    wallet,
  );

  // ── Encode swap payload (needed for gas estimate) ─────────────────────────
  const payload = encodeSwap(
    poolKey,
    zeroForOne,
    normalizedAmountIn,
    amountOutMinBigInt,
  );

  // ── Fetch balances, symbols & decimals in parallel ──────────────────────
  const [
    inputTokenBalance,
    outputTokenBalance,
    inputTokenDecimals,
    outputTokenDecimals,
    inputTokenSymbol,
    outputTokenSymbol,
    nativeBalance,
    feeData,
  ] = await Promise.all([
    inputTokenContract.balanceOf(wallet.address),
    outputTokenContract.balanceOf(wallet.address),
    inputTokenContract.decimals(),
    outputTokenContract.decimals(),
    inputTokenContract.symbol(),
    outputTokenContract.symbol(),
    provider.getBalance(wallet.address),
    provider.getFeeData(),
  ]);

  const formattedInputBalance = ethers.formatUnits(
    inputTokenBalance,
    inputTokenDecimals,
  );
  const formattedOutputBalance = ethers.formatUnits(
    outputTokenBalance,
    outputTokenDecimals,
  );
  const formattedNativeBalance = ethers.formatEther(nativeBalance);

  // ── Wallet balances ───────────────────────────────────────────────────────
  console.log(`\n💼 Wallet Balances:`);
  console.log(
    `   ${inputTokenSymbol.padEnd(10)} (spending):  ${formattedInputBalance}`,
  );
  console.log(
    `   ${outputTokenSymbol.padEnd(10)} (receiving): ${formattedOutputBalance}`,
  );
  console.log(`   ETH        (gas):     ${formattedNativeBalance}`);

  // ── Token balance check (before spending gas on approvals) ────────────────
  if (inputTokenBalance < normalizedAmountIn) {
    console.error(
      `\n❌ Insufficient ${inputTokenSymbol} balance. Available: ${formattedInputBalance}, Required: ${amountIn}`,
    );
    process.exit(1);
  }
  console.log(`\n✅ Token balance check passed.`);

  // 1. Approve Permit2 to spend the input token
  await approveToken(inputToken, normalizedAmountIn, permitAddress, wallet);

  // 2. Permit router via Permit2 — must happen before estimateGas/simulate
  //    because router.execute checks Permit2 allowance during simulation
  await permitTokenToRouter(
    inputToken,
    normalizedAmountIn,
    deadline,
    permit2,
    routerAddress,
  );

  await new Promise((resolve) => setTimeout(resolve, 5000));
  // ── Gas estimate & simulation (Permit2 allowance is now set) ──────────────
  console.log(`\n⛽ Estimating gas...`);
  const [estimatedGas] = await Promise.all([
    router.execute.estimateGas("0x10", [payload], deadline),
  ]);

  const gasLimit = (estimatedGas * 120n) / 100n;
  const gasPrice = feeData.gasPrice ?? feeData.maxFeePerGas;
  const estimatedGasCostWei = gasLimit * gasPrice;
  const estimatedGasCostEth = ethers.formatEther(estimatedGasCostWei);

  console.log(`   Estimated gas units:   ${estimatedGas.toString()}`);
  console.log(`   Gas limit (w/ buffer): ${gasLimit.toString()}`);
  console.log(
    `   Gas price:             ${ethers.formatUnits(gasPrice, "gwei")} gwei`,
  );
  console.log(`   Estimated cost:        ${estimatedGasCostEth} ETH`);

  if (nativeBalance < estimatedGasCostWei) {
    console.error(
      `\n❌ Insufficient ETH for gas. Available: ${formattedNativeBalance} ETH, Required: ${estimatedGasCostEth} ETH`,
    );
    process.exit(1);
  }
  console.log(`✅ Gas check passed.\n`);

  // ── Swap simulation ───────────────────────────────────────────────────────
  const simPassed = await simulateSwap(router, payload, deadline, wallet);
  if (!simPassed) process.exit(1);

  console.log(); // spacing

  // 3. Execute swap
  console.log(`\n🚀 Submitting swap transaction...`);
  const tx = await router.execute("0x10", [payload], deadline, { gasLimit });
  console.log(`⏳ Waiting for confirmation... tx: ${tx.hash}`);
  const receipt = await tx.wait();

  // ── Actual gas cost ───────────────────────────────────────────────────────
  const actualGasCostWei = receipt.gasUsed * receipt.gasPrice;
  const actualGasCostEth = ethers.formatEther(actualGasCostWei);

  // ── Post-swap balances ────────────────────────────────────────────────────
  const [newInputBalance, newOutputBalance] = await Promise.all([
    inputTokenContract.balanceOf(wallet.address),
    outputTokenContract.balanceOf(wallet.address),
  ]);
  const formattedNewInputBalance = ethers.formatUnits(
    newInputBalance,
    inputTokenDecimals,
  );
  const formattedNewOutputBalance = ethers.formatUnits(
    newOutputBalance,
    outputTokenDecimals,
  );

  console.log(`\n✅ Swap confirmed!`);
  console.log(`   Hash:          ${receipt.hash}`);
  console.log(`   Block:         ${receipt.blockNumber}`);
  console.log(`   Gas used:      ${receipt.gasUsed.toString()}`);
  console.log(`   Actual cost:   ${actualGasCostEth} ETH`);
  console.log(`\n💼 Updated Wallet Balances:`);
  console.log(
    `   ${inputTokenSymbol?.padEnd(10)}: ${formattedInputBalance} → ${formattedNewInputBalance}`,
  );
  console.log(
    `   ${outputTokenSymbol?.padEnd(10)}: ${formattedOutputBalance} → ${formattedNewOutputBalance}`,
  );

  return receipt;
}

main().catch((err) => {
  console.error(`\n❌ Swap failed:`, err?.reason ?? err?.message ?? err);
  process.exit(1);
});
