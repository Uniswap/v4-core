// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Pool} from "../libraries/Pool.sol";

contract TickTest {
    using Pool for Pool.State;

    Pool.State public pool;

    function ticks(int24 tick) external view returns (Pool.TickInfo memory) {
        return pool.ticks[tick];
    }

    function tickSpacingToMaxLiquidityPerTick(int24 tickSpacing) external pure returns (uint128) {
        return Pool.tickSpacingToMaxLiquidityPerTick(tickSpacing);
    }

    function getGasCostOfTickSpacingToMaxLiquidityPerTick(int24 tickSpacing) external view returns (uint256) {
        uint256 gasBefore = gasleft();
        Pool.tickSpacingToMaxLiquidityPerTick(tickSpacing);
        return gasBefore - gasleft();
    }

    function setTick(int24 tick, Pool.TickInfo memory info) external {
        pool.ticks[tick] = info;
    }

    function getFeeGrowthInside(
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128
    ) external returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
        pool.slot0.tick = tickCurrent;
        pool.feeGrowthGlobal0X128 = feeGrowthGlobal0X128;
        pool.feeGrowthGlobal1X128 = feeGrowthGlobal1X128;
        return pool.getFeeGrowthInside(tickLower, tickUpper);
    }

    function update(
        int24 tick,
        int24 tickCurrent,
        int128 liquidityDelta,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128,
        bool upper
    ) external returns (bool flipped, uint128 liquidityGrossAfter) {
        pool.slot0.tick = tickCurrent;
        pool.feeGrowthGlobal0X128 = feeGrowthGlobal0X128;
        pool.feeGrowthGlobal1X128 = feeGrowthGlobal1X128;
        return pool.updateTick(tick, liquidityDelta, upper);
    }

    function clear(int24 tick) external {
        pool.clearTick(tick);
    }

    function cross(int24 tick, uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128)
        external
        returns (int128 liquidityNet)
    {
        return pool.crossTick(tick, feeGrowthGlobal0X128, feeGrowthGlobal1X128);
    }
}
