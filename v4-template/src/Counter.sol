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
import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

import {SimpleLending} from "./SimpleLending.sol";

interface ISimpleLending {
    function borrow(uint256 collateralAssetPrice, uint256 borrowAssetPrice) external;
    function repay() external;
}

contract Counter is BaseHook {
    using PoolIdLibrary for PoolKey;
    IPyth pyth;
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

    // ---------------------------------------------
    // Constructor
    // ---------------------------------------------
    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        pyth = IPyth(address(0xDd24F84d36BF92C65F92307595335bdFab5Bbd21));
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
        PythStructs.Price memory price = pyth.getPriceNoOlderThan(priceFeedId, 600);
        uint ethPrice18Decimals = (uint(uint64(price.price)) * (10 ** 18)) /
        (10 ** uint8(uint32(-1 * price.expo)));
        uint oneDollarInWei = ((10 ** 18) * (10 ** 18)) / ethPrice18Decimals;
        //emit event with human readable strings amount and messages
        emit MockPriceFetched(oneDollarInWei.toString(), "oneDollarInWei");




        
        //emit event with human readable strings amount and messages
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

    function fund () public payable {}
 }
