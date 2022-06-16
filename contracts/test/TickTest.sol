// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {Tick} from '../libraries/Tick.sol';

contract TickTest {
    using Tick for mapping(int24 => Tick.Info);

    mapping(int24 => Tick.Info) public ticks;

    function tickSpacingToMaxLiquidityPerTick(int24 tickSpacing) external pure returns (uint128) {
        return Tick.tickSpacingToMaxLiquidityPerTick(tickSpacing);
    }

    function getGasCostOfTickSpacingToMaxLiquidityPerTick(int24 tickSpacing) external view returns (uint256) {
        uint256 gasBefore = gasleft();
        Tick.tickSpacingToMaxLiquidityPerTick(tickSpacing);
        return gasBefore - gasleft();
    }

    function setTick(int24 tick, Tick.Info memory info) external {
        ticks[tick] = info;
    }

    function getFeeGrowthInside(
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128
    ) external view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
        return ticks.getFeeGrowthInside(tickLower, tickUpper, tickCurrent, feeGrowthGlobal0X128, feeGrowthGlobal1X128);
    }

    function update(
        int24 tick,
        int24 tickCurrent,
        int128 liquidityDelta,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128,
        bool upper
    ) external returns (bool flipped, uint128 liquidityGrossAfter) {
        return ticks.update(tick, tickCurrent, liquidityDelta, feeGrowthGlobal0X128, feeGrowthGlobal1X128, upper);
    }

    function clear(int24 tick) external {
        ticks.clear(tick);
    }

    function cross(
        int24 tick,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128
    ) external returns (int128 liquidityNet) {
        return ticks.cross(tick, feeGrowthGlobal0X128, feeGrowthGlobal1X128);
    }
}
