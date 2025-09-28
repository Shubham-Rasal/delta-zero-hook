"use strict";
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
var __generator = (this && this.__generator) || function (thisArg, body) {
    var _ = { label: 0, sent: function() { if (t[0] & 1) throw t[1]; return t[1]; }, trys: [], ops: [] }, f, y, t, g = Object.create((typeof Iterator === "function" ? Iterator : Object).prototype);
    return g.next = verb(0), g["throw"] = verb(1), g["return"] = verb(2), typeof Symbol === "function" && (g[Symbol.iterator] = function() { return this; }), g;
    function verb(n) { return function (v) { return step([n, v]); }; }
    function step(op) {
        if (f) throw new TypeError("Generator is already executing.");
        while (g && (g = 0, op[0] && (_ = 0)), _) try {
            if (f = 1, y && (t = op[0] & 2 ? y["return"] : op[0] ? y["throw"] || ((t = y["return"]) && t.call(y), 0) : y.next) && !(t = t.call(y, op[1])).done) return t;
            if (y = 0, t) op = [op[0] & 2, t.value];
            switch (op[0]) {
                case 0: case 1: t = op; break;
                case 4: _.label++; return { value: op[1], done: false };
                case 5: _.label++; y = op[1]; op = [0]; continue;
                case 7: op = _.ops.pop(); _.trys.pop(); continue;
                default:
                    if (!(t = _.trys, t = t.length > 0 && t[t.length - 1]) && (op[0] === 6 || op[0] === 2)) { _ = 0; continue; }
                    if (op[0] === 3 && (!t || (op[1] > t[0] && op[1] < t[3]))) { _.label = op[1]; break; }
                    if (op[0] === 6 && _.label < t[1]) { _.label = t[1]; t = op; break; }
                    if (t && _.label < t[2]) { _.label = t[2]; _.ops.push(op); break; }
                    if (t[2]) _.ops.pop();
                    _.trys.pop(); continue;
            }
            op = body.call(thisArg, _);
        } catch (e) { op = [6, e]; y = 0; } finally { f = t = 0; }
        if (op[0] & 5) throw op[1]; return { value: op[0] ? op[1] : void 0, done: true };
    }
};
Object.defineProperty(exports, "__esModule", { value: true });
var ethers_1 = require("ethers");
var v4_sdk_1 = require("@uniswap/v4-sdk");
var universal_router_sdk_1 = require("@uniswap/universal-router-sdk");
var hermes_client_1 = require("@pythnetwork/hermes-client");
// Config will be created in main function
var UNIVERSAL_ROUTER_ADDRESS = "0x3A9D48AB9751398BbFa63ad67599Bb04e4BdF98b"; // Change the Universal Router address as per the chain
var UNIVERSAL_ROUTER_ABI = [
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
];
var provider = new ethers_1.ethers.providers.JsonRpcProvider("https://ethereum-sepolia-rpc.publicnode.com");
var signer = new ethers_1.ethers.Wallet("0x8f3092541ef889aa7c0c6c3f81f0c607a63dc75204003b57c1ce2c51570b490c", provider);
var universalRouter = new ethers_1.ethers.Contract(UNIVERSAL_ROUTER_ADDRESS, UNIVERSAL_ROUTER_ABI, signer);
function main() {
    return __awaiter(this, void 0, void 0, function () {
        var connection, priceIds, priceFeedUpdateData, CurrentConfig, v4Planner, routePlanner, deadline, encodedActions, txOptions, tx, receipt;
        return __generator(this, function (_a) {
            switch (_a.label) {
                case 0:
                    connection = new hermes_client_1.HermesClient("https://hermes.pyth.network");
                    priceIds = ["0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace"];
                    return [4 /*yield*/, connection.getLatestPriceUpdates(priceIds)];
                case 1:
                    priceFeedUpdateData = _a.sent();
                    console.log("Retrieved Pyth price update:");
                    console.log(priceFeedUpdateData);
                    console.log("Starting swap transaction...");
                    CurrentConfig = {
                        poolKey: {
                            currency0: "0x0000000000000000000000000000000000000000",
                            currency1: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238",
                            fee: 500,
                            tickSpacing: 10,
                            hooks: "0x06a06b5ec0170EE061863ac861dD7B9Ea5554Ac0",
                        },
                        zeroForOne: true, // The direction of swap is ETH to USDC. Change it to 'false' for the reverse direction
                        amountIn: ethers_1.ethers.utils.parseUnits('0.001', 18).toString(),
                        amountOutMinimum: "0", // No minimum amount out (be careful with this in production!)
                        hookData: "0x".concat(priceFeedUpdateData.binary.data[0])
                    };
                    v4Planner = new v4_sdk_1.V4Planner();
                    routePlanner = new universal_router_sdk_1.RoutePlanner();
                    deadline = Math.floor(Date.now() / 1000) + 3600;
                    console.log("Deadline:", deadline);
                    // Add the swap action
                    v4Planner.addAction(v4_sdk_1.Actions.SWAP_EXACT_IN_SINGLE, [CurrentConfig]);
                    // Add settle action to pay tokens
                    v4Planner.addAction(v4_sdk_1.Actions.SETTLE_ALL, [CurrentConfig.poolKey.currency0, CurrentConfig.amountIn]);
                    // Add take action to receive tokens
                    v4Planner.addAction(v4_sdk_1.Actions.TAKE_ALL, [CurrentConfig.poolKey.currency1, CurrentConfig.amountOutMinimum]);
                    encodedActions = v4Planner.finalize();
                    routePlanner.addCommand(universal_router_sdk_1.CommandType.V4_SWAP, [v4Planner.actions, v4Planner.params]);
                    txOptions = {
                        value: CurrentConfig.amountIn
                    };
                    console.log("Commands:", routePlanner.commands);
                    console.log("Encoded actions:", encodedActions);
                    console.log("Deadline:", deadline);
                    console.log("TX options:", txOptions);
                    return [4 /*yield*/, universalRouter.execute(routePlanner.commands, [encodedActions], deadline, txOptions)];
                case 2:
                    tx = _a.sent();
                    return [4 /*yield*/, tx.wait()];
                case 3:
                    receipt = _a.sent();
                    console.log('Swap completed! Transaction hash:', receipt.transactionHash);
                    return [2 /*return*/];
            }
        });
    });
}
main();
