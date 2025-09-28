// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {
    IPoolManager,
    SwapParams,
    ModifyLiquidityParams
} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import { StateLibrary } from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {
    BeforeSwapDelta,
    BeforeSwapDeltaLibrary
} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

import {SimpleLending} from "./SimpleLending.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

interface ISimpleLending {
    function borrow(uint256 collateralAssetPrice, uint256 borrowAssetPrice) external;
    function repay(uint256 amount) external payable;
}

contract Counter is BaseHook {
    using PoolIdLibrary for PoolKey;
    IPyth pyth;
    ISimpleLending simpleLending;
    IERC20 pyusd;
    // ---------------------------------------------
    // State tracking
    // ---------------------------------------------
    mapping(PoolId => uint256) public beforeSwapCount;
    mapping(PoolId => uint256) public afterSwapCount;

    mapping(PoolId => uint256) public beforeAddLiquidityCount;
    mapping(PoolId => uint256) public beforeRemoveLiquidityCount;

    // ---------------------------------------------
    // Events
    // ---------------------------------------------
    event BeforeSwapExecuted(PoolId poolId, uint256 newCount);
    event AfterSwapExecuted(PoolId poolId, uint256 newCount);

    //human readable strings amount and messages
    event MockPriceFetched(
        string amount,
        string message
    );
    event MockAaveData(uint256 borrowRate, uint256 debt, uint256 collateral);
    event MockLpFee(uint256 feeBps);
    event DebtRatioCalculated(uint256 ratio);
    event RebalanceAction(string action, uint256 amount);
    event ImbalanceCalculated(uint256 imbalance);

    // ---------------------------------------------
    // Constructor
    // ---------------------------------------------
    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        pyth = IPyth(address(0xDd24F84d36BF92C65F92307595335bdFab5Bbd21));
        simpleLending = ISimpleLending(address(0x7D05AFDF7D6D7865E8e3b6510D401394082861dA));
        pyusd = IERC20(address(0xCaC524BcA292aaade2DF8A05cC58F0a65B1B3bB9));
    }

    // ---------------------------------------------
    // Permissions
    // ---------------------------------------------
    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: true,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // ---------------------------------------------
    // Hooks
    // ---------------------------------------------
    function _beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        beforeSwapCount[key.toId()]++;
        emit BeforeSwapExecuted(key.toId(), beforeSwapCount[key.toId()]);
        return (
            BaseHook.beforeSwap.selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            0
        );
    }

    function _afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata,
        BalanceDelta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        afterSwapCount[key.toId()]++;

        bytes[] memory pythPriceUpdate = new bytes[](1);
        pythPriceUpdate[0] = hookData;

        uint fee = pyth.getUpdateFee(pythPriceUpdate);
        pyth.updatePriceFeeds{ value: fee }(pythPriceUpdate);
        
        bytes32 priceFeedId = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace; // ETH/USD
        PythStructs.Price memory oraclePrice = pyth.getPriceNoOlderThan(priceFeedId, 600);
        uint ethPrice18Decimals = (uint(uint64(oraclePrice.price)) * (10 ** 18)) /
        (10 ** uint8(uint32(-1 * oraclePrice.expo)));
        uint oneDollarInWei = ((10 ** 18) * (10 ** 18)) / ethPrice18Decimals;
        //emit event with human readable strings amount and messages
        emit MockPriceFetched("Price fetched successfully", "oneDollarInWei");

        //implement zero delta strategy based on the lending, lp fees and ticks
        _executeRebalanceStrategy(key);


        //emit event with human readable strings amount and messages
        return (BaseHook.afterSwap.selector, 0);
    }

    function _executeRebalanceStrategy(PoolKey calldata key) internal {
        (uint160 sqrtPriceX96, int24 currentTick, uint24 protocolFee, uint24 lpFee, ) = 
            getPoolState(poolManager, key);
        uint256 price = sqrtPriceToPrice(sqrtPriceX96);
        uint256 tick = uint256(int256(currentTick));

        // this is simulated because all the positions are of the same contract
        uint256 collateral = pyusd.balanceOf(address(simpleLending));
        uint256 debt = address(simpleLending).balance;

        uint256 lowerBound = tick * 95 / 100;  // tick * (1 - 0.05)
        uint256 upperBound = tick * 105 / 100;  // tick * (1 + 0.05)
        uint256 ethWorth = price * (lpFee + protocolFee - debt);
        uint256 usdcWorth = lpFee + protocolFee + collateral;
        uint256 imbalance = ethWorth - usdcWorth;
        
        if(price >= lowerBound && price <= upperBound) {
            if(imbalance > 0) {
                _handleRepayment(imbalance, price, lpFee, debt, 5);
            }
        } else if(price > upperBound) {
            _handleRepayment(imbalance, price, lpFee, debt, 25);
        } else if(price < lowerBound) {
            _handleBorrowing(imbalance, price, lpFee, debt);
        }
    }

    function _handleRepayment(uint256 imbalance, uint256 price, uint24 lpFee, uint256 debt, uint256 percentage) internal {
        uint256 repayAmount = (imbalance * percentage) / 100 / price;
        if(repayAmount > lpFee) {
            repayAmount = lpFee;
        }
        if(repayAmount > debt) {
            repayAmount = debt;
        }
        if(repayAmount > 0) {
            simpleLending.repay(repayAmount);
        }
    }

    function _handleBorrowing(uint256 imbalance, uint256 price, uint24 lpFee, uint256 debt) internal {
        uint256 depositAmount = (imbalance * 25) / 100;
        if(depositAmount > lpFee) {
            depositAmount = lpFee;
        }
        if(depositAmount > debt) {
            depositAmount = debt;
        }
        if(depositAmount > 0) {
            pyusd.transferFrom(address(this), address(simpleLending), depositAmount);
            simpleLending.borrow(1 * 10**15, price);
        }
    }

    function sqrtPriceToPrice(uint160 sqrtPriceX96) internal pure returns (uint256 price) {
        // Price = (sqrtPriceX96 / 2^96)^2
        // Multiply by 10^18 for 18 decimal precision
        uint256 priceX192 = uint256(sqrtPriceX96) * sqrtPriceX96;
        price = (priceX192 * 1e18) >> 192; // Divide by 2^192 and multiply by 10^18
    }

    function getPoolState(IPoolManager manager, PoolKey memory poolKey)
        internal
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee, uint128 liquidity)
    {
        PoolId poolId = poolKey.toId();
        (sqrtPriceX96, tick, protocolFee, lpFee) = StateLibrary.getSlot0(manager, poolId);
        liquidity = StateLibrary.getLiquidity(manager, poolId);
    }

    function _beforeAddLiquidity(
        address,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) internal override returns (bytes4) {
        beforeAddLiquidityCount[key.toId()]++;
        return BaseHook.beforeAddLiquidity.selector;
    }

    function _beforeRemoveLiquidity(
        address,
        PoolKey calldata key,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) internal override returns (bytes4) {
        beforeRemoveLiquidityCount[key.toId()]++;
        return BaseHook.beforeRemoveLiquidity.selector;
    }

    function fund () public payable {}
 }
