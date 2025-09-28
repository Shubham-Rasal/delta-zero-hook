import { SwapExactInSingle } from '@uniswap/v4-sdk'
import {ethers} from 'ethers'

import { Actions, V4Planner } from '@uniswap/v4-sdk'
import { CommandType, RoutePlanner } from '@uniswap/universal-router-sdk'
import { HermesClient } from '@pythnetwork/hermes-client';



// Config will be created in main function

const UNIVERSAL_ROUTER_ADDRESS = "0x3A9D48AB9751398BbFa63ad67599Bb04e4BdF98b" // Change the Universal Router address as per the chain

const UNIVERSAL_ROUTER_ABI = [
    {
      inputs: [
        { internalType: "bytes", name: "commands", type: "bytes" },
        { internalType: "bytes[]", name: "inputs", type: "bytes[]" },
        { internalType: "uint256", name: "deadline", type: "uint256" },
      ],
      name: "execute",
      outputs: [],
      stateMutability: "payable",
      type: "function",
    },
]  

const provider = new ethers.providers.JsonRpcProvider("https://ethereum-sepolia-rpc.publicnode.com");
const signer = new ethers.Wallet(
    "0x8f3092541ef889aa7c0c6c3f81f0c607a63dc75204003b57c1ce2c51570b490c",
    provider
  );

const universalRouter = new ethers.Contract(
    UNIVERSAL_ROUTER_ADDRESS,
    UNIVERSAL_ROUTER_ABI,
    signer
)

async function main() {
    const connection = new HermesClient("https://hermes.pyth.network");
    const priceIds = ["0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace" as string];
    const priceFeedUpdateData = await connection.getLatestPriceUpdates(priceIds);
    console.log("Retrieved Pyth price update:");
    console.log(priceFeedUpdateData);
    console.log(`0x${priceFeedUpdateData.binary.data[0]}`)
    console.log("Starting swap transaction...")

    const CurrentConfig: SwapExactInSingle = {
        poolKey: {
            currency0: "0x0000000000000000000000000000000000000000",
            currency1: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238",
            fee: 3000,
            tickSpacing: 60,
            hooks: "0x16303a8923f56eB57843a856ACf2FCEC80adcac0",
        },
        zeroForOne: true, // The direction of swap is ETH to USDC. Change it to 'false' for the reverse direction
        amountIn: ethers.utils.parseUnits('0.0001', 18).toString(), 
        amountOutMinimum: "0", // No minimum amount out (be careful with this in production!)
        hookData: `0x${priceFeedUpdateData.binary.data[0]}`
    }

    const v4Planner = new V4Planner()
    const routePlanner = new RoutePlanner()

    // Set deadline (1 hour from now)
    const deadline = Math.floor(Date.now() / 1000) + 3600

    console.log("Deadline:", deadline)

    // Add the swap action
    v4Planner.addAction(Actions.SWAP_EXACT_IN_SINGLE, [CurrentConfig]);
    
    // Add settle action to pay tokens
    v4Planner.addAction(Actions.SETTLE_ALL, [CurrentConfig.poolKey.currency0, CurrentConfig.amountIn]);
    
    // Add take action to receive tokens
    v4Planner.addAction(Actions.TAKE_ALL, [CurrentConfig.poolKey.currency1, CurrentConfig.amountOutMinimum]);

    const encodedActions = v4Planner.finalize()

    routePlanner.addCommand(CommandType.V4_SWAP, [v4Planner.actions, v4Planner.params])

    // Only needed for native ETH as input currency swaps
    const txOptions: any = {
        value: CurrentConfig.amountIn
    }

    console.log("Commands:", routePlanner.commands)
    console.log("Encoded actions:", encodedActions)
    console.log("Deadline:", deadline)
    console.log("TX options:", txOptions)

    const tx = await universalRouter.execute(
        routePlanner.commands,
        [encodedActions],
        deadline,
        txOptions
    )

    const receipt = await tx.wait()
    console.log('Swap completed! Transaction hash:', receipt.transactionHash)
}

main()