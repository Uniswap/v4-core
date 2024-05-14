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

contract Fuzzers is StdUtils {
    Vm internal constant _vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function boundLiquidityDelta(PoolKey memory key, int256 liquidityDelta) internal pure returns (int256) {
        return bound(
            liquidityDelta, 0.0000001e18, int256(uint256(Pool.tickSpacingToMaxLiquidityPerTick(key.tickSpacing)) / 2)
        );
    }

    function boundTicks(PoolKey memory key, int24 tickLower, int24 tickUpper) internal pure returns (int24, int24) {
        tickLower = int24(
            bound(
                int256(tickLower),
                int256(TickMath.minUsableTick(key.tickSpacing)),
                int256(TickMath.maxUsableTick(key.tickSpacing))
            )
        );
        tickUpper = int24(
            bound(
                int256(tickUpper),
                int256(TickMath.minUsableTick(key.tickSpacing)),
                int256(TickMath.maxUsableTick(key.tickSpacing))
            )
        );

        // round down ticks
        tickLower = (tickLower / key.tickSpacing) * key.tickSpacing;
        tickUpper = (tickUpper / key.tickSpacing) * key.tickSpacing;

        (tickLower, tickUpper) = tickLower < tickUpper ? (tickLower, tickUpper) : (tickUpper, tickLower);

        _vm.assume(tickLower != tickUpper);

        return (tickLower, tickUpper);
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
