import { createWalletClient, createPublicClient, http, parseEther, parseUnits } from "viem";
import { waitForTransactionReceipt } from "viem/actions";
import { privateKeyToAccount } from "viem/accounts";
import { baseSepolia } from "viem/chains";
import { getContract } from "viem";
import { erc20Abi } from "viem";

//0x3A9D48AB9751398BbFa63ad67599Bb04e4BdF98b
// Uniswap V4 Router ABI - swapExactTokensForTokens function
export const routerAbi = [
  {
    type: "function",
    name: "swapExactTokensForTokens",
    inputs: [
      {
        name: "amountIn",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "amountOutMin",
        type: "uint256",
        internalType: "uint256",
      },
      {
        name: "zeroForOne",
        type: "bool",
        internalType: "bool",
      },
      {
        name: "poolKey",
        type: "tuple",
        internalType: "struct PoolKey",
        components: [
          {
            name: "currency0",
            type: "address",
            internalType: "address",
          },
          {
            name: "currency1",
            type: "address",
            internalType: "address",
          },
          {
            name: "fee",
            type: "uint256",
            internalType: "uint24",
          },
          {
            name: "tickSpacing",
            type: "int256",
            internalType: "int24",
          },
          {
            name: "hooks",
            type: "address",
            internalType: "address",
          },
        ],
      },
      {
        name: "hookData",
        type: "bytes",
        internalType: "bytes",
      },
      {
        name: "receiver",
        type: "address",
        internalType: "address",
      },
      {
        name: "deadline",
        type: "uint256",
        internalType: "uint256",
      },
    ],
    outputs: [
      {
        name: "delta",
        type: "int256",
        internalType: "int256",
      },
    ],
    stateMutability: "payable",
  },
] as const;

// ERC20 ABI for approvals


async function run() {
  const account = privateKeyToAccount("0x8f3092541ef889aa7c0c6c3f81f0c607a63dc75204003b57c1ce2c51570b490c" as any);
  console.log("Account:", account.address);
  const walletClient = createWalletClient({
    account,
    chain: baseSepolia,
    transport: http("https://sepolia.base.org"),
  });

  const userAddress = "0x23178ccD27CDa5D5D18B211aD6648e189c1e16E1"
  
  const publicClient = createPublicClient({
    chain: baseSepolia,
    transport: http("https://sepolia.base.org"),
  });


  // Contract addresses from BaseScript.sol
  const token0Address = "0x0C62bcC5e5167ACB11CcfFE8CF58853625f94CF6"; // token0
  const token1Address = "0x28f25ca4149661E5157782C64635A8300Ced30cb"; // token1
  const hookContractAddress = "0xBB7484670184E3737f4f5e51916B8A745882CAc0";
  const swapRouterAddress = "0x71cD4Ea054F9Cb3D3BF6251A00673303411A7DD9"; // Base Sepolia V4 Router

  // Create contract instances
  const swapRouter = getContract({
    address: swapRouterAddress as any,
    abi: routerAbi,
    client: walletClient,
  });

  const token0 = getContract({
    address: token0Address as any,
    abi: erc20Abi,
    client: walletClient,
  });

  const token1 = getContract({
    address: token1Address as any,
    abi: erc20Abi,
    client: walletClient,
  });

  // PoolKey structure
  const poolKey = {
    currency0: token0Address as `0x${string}`,
    currency1: token1Address as `0x${string}`,
    fee: 3000n,
    tickSpacing: 60n,
    hooks: hookContractAddress as `0x${string}`,
  };

  // Swap parameters
  const amountIn = parseEther("1"); // 1 ETH
  const amountOutMin = 0n; // Very bad, but we want to allow for unlimited price impact
  const zeroForOne = true; // true if currency0 is being swapped for currency1
  const hookData = "0x504e41550100000003b801000000040d0011954100bdfa"; // Empty bytes
  const receiver = account.address; // Send to our address
  const deadline = Math.floor(Date.now() / 1000) + 30; // 30 seconds from now

  const token1Balance = await token1.read.balanceOf([userAddress]);
  console.log("Token1 balance:", token1Balance);

  const token0Balance = await token0.read.balanceOf([userAddress]);
  console.log("Token0 balance:", token0Balance);

  console.log("Starting swap transaction...");
  console.log("PoolKey:", poolKey);
  console.log("Amount in:", amountIn.toString());
  console.log("Zero for one:", zeroForOne);
  console.log("Receiver:", receiver);


  try {
    // Approve both tokens for the swap router
    console.log("Approving token0...");
    const approveToken0Hash = await token0.write.approve([
      swapRouterAddress,
      parseEther("1000"), // Approve a large amount
    ]);
    console.log("Token0 approval hash:", approveToken0Hash);


    // Wait for approvals to be mined
    await waitForTransactionReceipt(publicClient, { hash: approveToken0Hash });

    // Wait for 10 seconds
    await new Promise(resolve => setTimeout(resolve, 10000));

    console.log("Approving token1...");

    const approveToken1Hash = await token1.write.approve([
      swapRouterAddress,
      parseEther("1000"), // Approve a large amount
    ]);
    console.log("Token1 approval hash:", approveToken1Hash);

    // Wait for approvals to be mined
    await waitForTransactionReceipt(publicClient, { hash: approveToken0Hash });

    // Wait for 10 seconds
    await new Promise(resolve => setTimeout(resolve, 10000));

    await waitForTransactionReceipt(publicClient, { hash: approveToken1Hash });

    // Wait for 10 seconds
    await new Promise(resolve => setTimeout(resolve, 10000));

    // Execute swap
    console.log("Executing swap...");
    const swapHash = await swapRouter.write.swapExactTokensForTokens([
      amountIn,
      amountOutMin,
      zeroForOne,
      poolKey,
      hookData,
      receiver,
      BigInt(deadline),
    ]);

    console.log("Swap transaction hash:", swapHash);

    // Wait for 10 seconds
    await new Promise(resolve => setTimeout(resolve, 10000));

    // Wait for transaction to be mined
    const receipt = await waitForTransactionReceipt(publicClient, { hash: swapHash });
    console.log("Transaction receipt:", receipt);
  } catch (error) {
    console.error("Error executing swap:", error);
  }
}

run();
