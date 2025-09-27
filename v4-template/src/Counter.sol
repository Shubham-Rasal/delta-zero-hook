// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {
    IPoolManager,
    SwapParams,
    ModifyLiquidityParams
} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {
    BeforeSwapDelta,
    BeforeSwapDeltaLibrary
} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

contract Counter is BaseHook {
    using PoolIdLibrary for PoolKey;

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

    event MockPriceFetched(uint256 ethUsdPrice, uint256 usdcUsdPrice);
    event MockAaveData(uint256 borrowRate, uint256 debt, uint256 collateral);
    event MockLpFee(uint256 feeBps);
    event DebtRatioCalculated(uint256 ratio);
    event RebalanceAction(string action, uint256 amount);

    // ---------------------------------------------
    // Constructor
    // ---------------------------------------------
    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

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
        bytes calldata
    ) internal override returns (bytes4, int128) {
        afterSwapCount[key.toId()]++;
        emit AfterSwapExecuted(key.toId(), afterSwapCount[key.toId()]);

        // -------------------------------------------------
        // Mocked workflow: all values are hardcoded for now
        // -------------------------------------------------

        // 1. Mock price fetch from Pyth
        uint256 ethUsdPrice = 3000e8; // $3000
        uint256 usdcUsdPrice = 1e8;   // $1
        emit MockPriceFetched(ethUsdPrice, usdcUsdPrice);

        // 2. Mock Aave data
        uint256 borrowRate = 5e16; // 5%
        uint256 debt = 10 ether;
        uint256 collateral = 20 ether;
        emit MockAaveData(borrowRate, debt, collateral);

        // 3. Mock LP fee
        uint256 lpFeeBps = 30; // 0.3%
        emit MockLpFee(lpFeeBps);

        // 4. Mock debt ratio calculation
        uint256 debtRatio = (debt * 1e18) / collateral; // simple ratio
        emit DebtRatioCalculated(debtRatio);

        // 5. Mock rebalance action
        if (debtRatio < 1e18) {
            emit RebalanceAction("repay", 1 ether);
        } else if (debtRatio > 1e18) {
            emit RebalanceAction("borrow", 1 ether);
        } else {
            emit RebalanceAction("noop", 0);
        }

        return (BaseHook.afterSwap.selector, 0);
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
}
