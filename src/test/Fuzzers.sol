// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {TickMath} from "../libraries/TickMath.sol";
import {Pool} from "../libraries/Pool.sol";
import {PoolModifyLiquidityTest} from "./PoolModifyLiquidityTest.sol";
import {LiquidityAmounts} from "../../test/utils/LiquidityAmounts.sol";

contract Fuzzers is StdUtils {
    Vm internal constant _vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function boundLiquidityDelta(PoolKey memory key, int256 liquidityDelta) internal pure returns (int256) {
        return bound(liquidityDelta, 1, int256(uint256(Pool.tickSpacingToMaxLiquidityPerTick(key.tickSpacing)) / 2));
    }

    function getLiquidityDeltaFromAmounts(
        uint128 amount0Unbound,
        uint128 amount1Unbound,
        int24 tickLower,
        int24 tickUpper,
        uint160 sqrtPriceX96
    ) internal pure returns (int256) {
        uint256 amount0 = bound(amount0Unbound, 0, uint256(type(uint128).max / 2));
        uint256 amount1 = bound(amount1Unbound, 0, uint256(type(uint128).max / 2));
        return int128(
            LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceX96,
                TickMath.getSqrtPriceAtTick(tickLower),
                TickMath.getSqrtPriceAtTick(tickUpper),
                amount0,
                amount1
            )
        );
    }

    function boundTicks(int24 tickLower, int24 tickUpper, int24 tickSpacing) internal pure returns (int24, int24) {
        tickLower = int24(
            bound(
                int256(tickLower),
                int256(TickMath.minUsableTick(tickSpacing)),
                int256(TickMath.maxUsableTick(tickSpacing))
            )
        );
        tickUpper = int24(
            bound(
                int256(tickUpper),
                int256(TickMath.minUsableTick(tickSpacing)),
                int256(TickMath.maxUsableTick(tickSpacing))
            )
        );

        // round down ticks
        tickLower = (tickLower / tickSpacing) * tickSpacing;
        tickUpper = (tickUpper / tickSpacing) * tickSpacing;

        (tickLower, tickUpper) = tickLower < tickUpper ? (tickLower, tickUpper) : (tickUpper, tickLower);

        _vm.assume(tickLower != tickUpper);

        return (tickLower, tickUpper);
    }

    function boundTicks(PoolKey memory key, int24 tickLower, int24 tickUpper) internal pure returns (int24, int24) {
        return boundTicks(tickLower, tickUpper, key.tickSpacing);
    }

    function createRandomSqrtPriceX96(PoolKey memory key, int256 seed) internal pure returns (uint160) {
        int24 tickSpacing = key.tickSpacing;
        int256 min = int256(TickMath.minUsableTick(tickSpacing));
        int256 max = int256(TickMath.maxUsableTick(tickSpacing));
        int256 randomTick = bound(seed, min, max);
        return TickMath.getSqrtPriceAtTick(int24(randomTick));
    }

    /// @dev Obtain fuzzed parameters for creating liquidity
    /// @param key The pool key
    /// @param params IPoolManager.ModifyLiquidityParams
    function createFuzzyLiquidityParamsFromAmounts(
        PoolKey memory key,
        IPoolManager.ModifyLiquidityParams memory params,
        uint128 amount0,
        uint128 amount1,
        uint160 sqrtPriceX96
    ) internal pure returns (IPoolManager.ModifyLiquidityParams memory result) {
        (result.tickLower, result.tickUpper) = boundTicks(key, params.tickLower, params.tickUpper);
        result.liquidityDelta =
            getLiquidityDeltaFromAmounts(amount0, amount1, result.tickLower, result.tickUpper, sqrtPriceX96);
        result.liquidityDelta = boundLiquidityDelta(key, result.liquidityDelta);
    }

    /// @dev Obtain fuzzed parameters for creating liquidity
    /// @param key The pool key
    /// @param params IPoolManager.ModifyLiquidityParams
    function createFuzzyLiquidityParams(PoolKey memory key, IPoolManager.ModifyLiquidityParams memory params)
        internal
        pure
        returns (IPoolManager.ModifyLiquidityParams memory result)
    {
        (result.tickLower, result.tickUpper) = boundTicks(key, params.tickLower, params.tickUpper);
        int256 liquidityDelta = boundLiquidityDelta(key, params.liquidityDelta);
        result.liquidityDelta = liquidityDelta;
    }

    function createFuzzyLiquidity(
        PoolModifyLiquidityTest modifyLiquidityRouter,
        PoolKey memory key,
        IPoolManager.ModifyLiquidityParams memory params,
        bytes memory hookData
    ) internal returns (IPoolManager.ModifyLiquidityParams memory result, BalanceDelta delta) {
        result = createFuzzyLiquidityParams(key, params);
        delta = modifyLiquidityRouter.modifyLiquidity(key, result, hookData);
    }
}
