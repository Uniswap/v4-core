// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {GasSnapshot} from "../../lib/forge-gas-snapshot/src/GasSnapshot.sol";
import {Constants} from "./utils/Constants.sol";
import {Pool} from "../../contracts/libraries/Pool.sol";
import {TickMath} from "../../contracts/libraries/TickMath.sol";

contract TickTest is Test, GasSnapshot {
    using Pool for Pool.State;

    int24 constant LOW_TICK_SPACING = 10;
    int24 constant MEDIUM_TICK_SPACING = 60;
    int24 constant HIGH_TICK_SPACING = 200;

    Pool.State public pool;

    function ticks(int24 tick) internal view returns (Pool.TickInfo memory) {
        return pool.ticks[tick];
    }

    function tickSpacingToMaxLiquidityPerTick(int24 tickSpacing) internal pure returns (uint128) {
        return Pool.tickSpacingToMaxLiquidityPerTick(tickSpacing);
    }

    function setTick(int24 tick, Pool.TickInfo memory info) internal {
        pool.ticks[tick] = info;
    }

    function getFeeGrowthInside(
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128
    ) internal returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
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
    ) internal returns (bool flipped, uint128 liquidityGrossAfter) {
        pool.slot0.tick = tickCurrent;
        pool.feeGrowthGlobal0X128 = feeGrowthGlobal0X128;
        pool.feeGrowthGlobal1X128 = feeGrowthGlobal1X128;
        return pool.updateTick(tick, liquidityDelta, upper);
    }

    function clear(int24 tick) internal {
        pool.clearTick(tick);
    }

    function cross(int24 tick, uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128)
        internal
        returns (int128 liquidityNet)
    {
        return pool.crossTick(tick, feeGrowthGlobal0X128, feeGrowthGlobal1X128);
    }

    function getMinTick(int24 tickSpacing) internal pure returns (int256) {
        return (Constants.MIN_TICK / tickSpacing) * tickSpacing;
    }

    function getMaxTick(int24 tickSpacing) internal pure returns (int256) {
        return (Constants.MAX_TICK / tickSpacing) * tickSpacing;
    }

    function checkCantOverflow(int24 tickSpacing, uint128 maxLiquidityPerTick) internal {
        assertLe(
            uint256(
                uint256(maxLiquidityPerTick)
                    * uint256((getMaxTick(tickSpacing) - getMinTick(tickSpacing)) / tickSpacing + 1)
            ),
            uint256(Constants.MAX_UINT128)
        );
    }

    function testTick_tickSpacingToMaxLiquidityPerTick_returnsTheCorrectValueForLowFee() public {
        uint128 maxLiquidityPerTick = tickSpacingToMaxLiquidityPerTick(LOW_TICK_SPACING);

        assertEq(maxLiquidityPerTick, 1917565579412846627735051215301243);
        checkCantOverflow(LOW_TICK_SPACING, maxLiquidityPerTick);
    }

    function testTick_tickSpacingToMaxLiquidityPerTick_returnsTheCorrectValueForMediumFee() public {
        uint128 maxLiquidityPerTick = tickSpacingToMaxLiquidityPerTick(MEDIUM_TICK_SPACING);

        assertEq(maxLiquidityPerTick, 11505069308564788430434325881101413); // 113.1 bits
        checkCantOverflow(MEDIUM_TICK_SPACING, maxLiquidityPerTick);
    }

    function testTick_tickSpacingToMaxLiquidityPerTick_returnsTheCorrectValueForHighFee() public {
        uint128 maxLiquidityPerTick = tickSpacingToMaxLiquidityPerTick(HIGH_TICK_SPACING);

        assertEq(maxLiquidityPerTick, 38347205785278154309959589375342946); // 114.7 bits
        checkCantOverflow(HIGH_TICK_SPACING, maxLiquidityPerTick);
    }

    function testTick_tickSpacingToMaxLiquidityPerTick_returnsTheCorrectValueFor1() public {
        uint128 maxLiquidityPerTick = tickSpacingToMaxLiquidityPerTick(1);

        assertEq(maxLiquidityPerTick, 191757530477355301479181766273477); // 126 bits
        checkCantOverflow(1, maxLiquidityPerTick);
    }

    function testTick_tickSpacingToMaxLiquidityPerTick_returnsTheCorrectValueForEntireRange() public {
        uint128 maxLiquidityPerTick = tickSpacingToMaxLiquidityPerTick(887272);

        assertEq(maxLiquidityPerTick, Constants.MAX_UINT128 / 3); // 126 bits
        checkCantOverflow(887272, maxLiquidityPerTick);
    }

    function testTick_tickSpacingToMaxLiquidityPerTick_returnsTheCorrectValueFor2302() public {
        uint128 maxLiquidityPerTick = tickSpacingToMaxLiquidityPerTick(2302);

        assertEq(maxLiquidityPerTick, 440854192570431170114173285871668350); // 118 bits
        checkCantOverflow(2302, maxLiquidityPerTick);
    }

    function testTick_tickSpacingToMaxLiquidityPerTick_gasCostMinTickSpacing() public {
        snapStart("tickSpacingToMaxLiquidityPerTick_gasCostMinTickSpacing");
        tickSpacingToMaxLiquidityPerTick(1);
        snapEnd();
    }

    function testTick_tickSpacingToMaxLiquidityPerTick_gasCost60TickSpacing() public {
        snapStart("tickSpacingToMaxLiquidityPerTick_gasCost60TickSpacing");
        tickSpacingToMaxLiquidityPerTick(60);
        snapEnd();
    }

    function testTick_tickSpacingToMaxLiquidityPerTick_gasCostMaxTickSpacing() public {
        int24 MAX_TICK_SPACING = 32767;

        snapStart("tickSpacingToMaxLiquidityPerTick_gasCostMaxTickSpacing");
        tickSpacingToMaxLiquidityPerTick(MAX_TICK_SPACING);
        snapEnd();
    }

    function testTick_getFeeGrowthInside_returnsAllForTwoUninitializedTicksIfTickIsInside() public {
        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = getFeeGrowthInside(-2, 2, 0, 15, 15);

        assertEq(feeGrowthInside0X128, 15);
        assertEq(feeGrowthInside1X128, 15);
    }

    function testTick_getFeeGrowthInside_returns0ForTwoUninitializedTicksIfTickIsAbove() public {
        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = getFeeGrowthInside(-2, 2, 4, 15, 15);

        assertEq(feeGrowthInside0X128, 0);
        assertEq(feeGrowthInside1X128, 0);
    }

    function testTick_getFeeGrowthInside_returns0ForTwoUninitializedTicksIfTickIsBelow() public {
        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = getFeeGrowthInside(-2, 2, -4, 15, 15);

        assertEq(feeGrowthInside0X128, 0);
        assertEq(feeGrowthInside1X128, 0);
    }

    function testTick_getFeeGrowthInside_subtractsUpperTickIfBelow() public {
        Pool.TickInfo memory info;

        info.feeGrowthOutside0X128 = 2;
        info.feeGrowthOutside1X128 = 3;
        info.liquidityGross = 0;
        info.liquidityNet = 0;

        setTick(2, info);

        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = getFeeGrowthInside(-2, 2, 0, 15, 15);

        assertEq(feeGrowthInside0X128, 13);
        assertEq(feeGrowthInside1X128, 12);
    }

    function testTick_getFeeGrowthInside_subtractsLowerTickIfAbove() public {
        Pool.TickInfo memory info;

        info.feeGrowthOutside0X128 = 2;
        info.feeGrowthOutside1X128 = 3;
        info.liquidityGross = 0;
        info.liquidityNet = 0;

        setTick(-2, info);

        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = getFeeGrowthInside(-2, 2, 0, 15, 15);

        assertEq(feeGrowthInside0X128, 13);
        assertEq(feeGrowthInside1X128, 12);
    }

    function testTick_getFeeGrowthInside_subtractsUpperAndLowerTickIfInside() public {
        Pool.TickInfo memory info;

        info.feeGrowthOutside0X128 = 2;
        info.feeGrowthOutside1X128 = 3;
        info.liquidityGross = 0;
        info.liquidityNet = 0;

        setTick(-2, info);

        info.feeGrowthOutside0X128 = 4;
        info.feeGrowthOutside1X128 = 1;
        info.liquidityGross = 0;
        info.liquidityNet = 0;

        setTick(2, info);

        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = getFeeGrowthInside(-2, 2, 0, 15, 15);

        assertEq(feeGrowthInside0X128, 9);
        assertEq(feeGrowthInside1X128, 11);
    }

    function testTick_getFeeGrowthInside_worksCorrectlyWithOverflowOnInsideTick() public {
        Pool.TickInfo memory info;

        info.feeGrowthOutside0X128 = Constants.MAX_UINT256 - 3;
        info.feeGrowthOutside1X128 = Constants.MAX_UINT256 - 2;
        info.liquidityGross = 0;
        info.liquidityNet = 0;

        setTick(-2, info);

        info.feeGrowthOutside0X128 = 3;
        info.feeGrowthOutside1X128 = 5;
        info.liquidityGross = 0;
        info.liquidityNet = 0;

        setTick(2, info);

        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = getFeeGrowthInside(-2, 2, 0, 15, 15);

        assertEq(feeGrowthInside0X128, 16);
        assertEq(feeGrowthInside1X128, 13);
    }

    function testTick_update_flipsFromZeroToNonzero() public {
        (bool flipped, uint128 liquidityGrossAfter) = update(0, 0, 1, 0, 0, false);

        assertEq(flipped, true);
        assertEq(liquidityGrossAfter, 1);
    }

    function testTick_update_doesNotFlipFromNonzeroToGreaterNonzero() public {
        update(0, 0, 1, 0, 0, false);
        (bool flipped, uint128 liquidityGrossAfter) = update(0, 0, 1, 0, 0, false);

        assertEq(flipped, false);
        assertEq(liquidityGrossAfter, 2);
    }

    function testTick_update_flipsFromNonzeroToZero() public {
        update(0, 0, 1, 0, 0, false);
        (bool flipped, uint128 liquidityGrossAfter) = update(0, 0, -1, 0, 0, false);

        assertEq(flipped, true);
        assertEq(liquidityGrossAfter, 0);
    }

    function testTick_update_doesNotFlipFromNonzeroToLesserZero() public {
        update(0, 0, 2, 0, 0, false);
        (bool flipped, uint128 liquidityGrossAfter) = update(0, 0, -1, 0, 0, false);

        assertEq(flipped, false);
        assertEq(liquidityGrossAfter, 1);
    }

    function testTick_update_netsTheLiquidityBasedOnUpperFlag() public {
        Pool.TickInfo memory tickInfo;

        update(0, 0, 2, 0, 0, false);
        update(0, 0, 1, 0, 0, true);
        update(0, 0, 3, 0, 0, true);
        update(0, 0, 1, 0, 0, false);
        tickInfo = ticks(0);

        assertEq(tickInfo.liquidityGross, 2 + 1 + 3 + 1);
        assertEq(tickInfo.liquidityNet, 2 - 1 - 3 + 1);
    }

    function testTick_update_revertsOnOverflowLiquidityGross() public {
        update(0, 0, int128(Constants.MAX_UINT128 / 2 - 1), 0, 0, false);

        vm.expectRevert();
        update(0, 0, int128(Constants.MAX_UINT128 / 2 - 1), 0, 0, false);
    }

    function testTick_update_assumesAllGrowthHappensBelowTicksLteCurrentTick() public {
        Pool.TickInfo memory tickInfo;

        update(1, 1, 1, 1, 2, false);
        tickInfo = ticks(1);

        assertEq(tickInfo.feeGrowthOutside0X128, 1);
        assertEq(tickInfo.feeGrowthOutside1X128, 2);
    }

    function testTick_update_doesNotSetAnyGrowthFieldsIfTickIsAlreadyInitialized() public {
        Pool.TickInfo memory tickInfo;

        update(1, 1, 1, 1, 2, false);
        update(1, 1, 1, 6, 7, false);
        tickInfo = ticks(1);

        assertEq(tickInfo.feeGrowthOutside0X128, 1);
        assertEq(tickInfo.feeGrowthOutside1X128, 2);
    }

    function testTick_update_doesNotSetAnyGrowthFieldsForTicksGtCurrentTick() public {
        Pool.TickInfo memory tickInfo;

        update(2, 1, 1, 1, 2, false);
        tickInfo = ticks(2);

        assertEq(tickInfo.feeGrowthOutside0X128, 0);
        assertEq(tickInfo.feeGrowthOutside1X128, 0);
    }

    function testTick_update_liquidityParsing_parsesMaxUint128StoredLiquidityGrossBeforeUpdate() public {
        Pool.TickInfo memory info;

        info.feeGrowthOutside0X128 = 0;
        info.feeGrowthOutside1X128 = 0;
        info.liquidityGross = Constants.MAX_UINT128;
        info.liquidityNet = 0;

        setTick(2, info);
        update(2, 1, -1, 1, 2, false);

        info = ticks(2);

        assertEq(info.liquidityGross, Constants.MAX_UINT128 - 1);
        assertEq(info.liquidityNet, -1);
    }

    function testTick_update_liquidityParsing_parsesMaxUint128StoredLiquidityGrossAfterUpdate() public {
        Pool.TickInfo memory info;

        info.feeGrowthOutside0X128 = 0;
        info.feeGrowthOutside1X128 = 0;
        info.liquidityGross = (Constants.MAX_UINT128 / 2) + 1;
        info.liquidityNet = 0;

        setTick(2, info);

        update(2, 1, int128(Constants.MAX_UINT128 / 2), 1, 2, false);

        info = ticks(2);

        assertEq(info.liquidityGross, Constants.MAX_UINT128);
        assertEq(info.liquidityNet, int128(Constants.MAX_UINT128 / 2));
    }

    function testTick_update_liquidityParsing_parsesMaxInt128StoredLiquidityGrossBeforeUpdate() public {
        Pool.TickInfo memory info;

        info.feeGrowthOutside0X128 = 0;
        info.feeGrowthOutside1X128 = 0;
        info.liquidityGross = 1;
        info.liquidityNet = int128(Constants.MAX_UINT128 / 2);

        setTick(2, info);
        update(2, 1, -1, 1, 2, false);

        info = ticks(2);

        assertEq(info.liquidityGross, 0);
        assertEq(info.liquidityNet, int128(Constants.MAX_UINT128 / 2 - 1));
    }

    function testTick_update_liquidityParsing_parsesMaxInt128StoredLiquidityGrossAfterUpdate() public {
        Pool.TickInfo memory info;

        info.feeGrowthOutside0X128 = 0;
        info.feeGrowthOutside1X128 = 0;
        info.liquidityGross = 0;
        info.liquidityNet = int128(Constants.MAX_UINT128 / 2 - 1);

        setTick(2, info);

        update(2, 1, 1, 1, 2, false);

        info = ticks(2);

        assertEq(info.liquidityGross, 1);
        assertEq(info.liquidityNet, int128(Constants.MAX_UINT128 / 2));
    }

    function testTick_clear_deletesAllTheDataInTheTick() public {
        Pool.TickInfo memory info;

        info.feeGrowthOutside0X128 = 1;
        info.feeGrowthOutside1X128 = 2;
        info.liquidityGross = 3;
        info.liquidityNet = 4;

        setTick(2, info);

        clear(2);

        info = ticks(2);

        assertEq(info.feeGrowthOutside0X128, 0);
        assertEq(info.feeGrowthOutside1X128, 0);
        assertEq(info.liquidityGross, 0);
        assertEq(info.liquidityNet, 0);
    }

    function testTick_cross_flipsTheGrowthVariables() public {
        Pool.TickInfo memory info;

        info.feeGrowthOutside0X128 = 1;
        info.feeGrowthOutside1X128 = 2;
        info.liquidityGross = 3;
        info.liquidityNet = 4;

        setTick(2, info);

        cross(2, 7, 9);

        info = ticks(2);

        assertEq(info.feeGrowthOutside0X128, 6);
        assertEq(info.feeGrowthOutside1X128, 7);
    }

    function testTick_cross_twoFlipsAreNoOp() public {
        Pool.TickInfo memory info;

        info.feeGrowthOutside0X128 = 1;
        info.feeGrowthOutside1X128 = 2;
        info.liquidityGross = 3;
        info.liquidityNet = 4;

        setTick(2, info);

        cross(2, 7, 9);
        cross(2, 7, 9);

        info = ticks(2);

        assertEq(info.feeGrowthOutside0X128, 1);
        assertEq(info.feeGrowthOutside1X128, 2);
    }

    function testTick_tickSpacingToParametersInvariants_fuzz(int24 tickSpacing) public {
        vm.assume(tickSpacing <= TickMath.MAX_TICK);
        vm.assume(tickSpacing > 0);

        int24 minTick = (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
        int24 maxTick = (TickMath.MAX_TICK / tickSpacing) * tickSpacing;

        uint128 maxLiquidityPerTick = Pool.tickSpacingToMaxLiquidityPerTick(tickSpacing);

        // symmetry around 0 tick
        assertEq(maxTick, -minTick);
        // positive max tick
        assertGt(maxTick, 0);
        // divisibility
        assertEq((maxTick - minTick) % tickSpacing, 0);

        uint256 numTicks = uint256(int256((maxTick - minTick) / tickSpacing)) + 1;
        // max liquidity at every tick is less than the cap
        assertGt(type(uint128).max, uint256(maxLiquidityPerTick) * numTicks);
    }
}
