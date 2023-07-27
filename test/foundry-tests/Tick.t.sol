// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {TickTest} from "../../contracts/test/TickTest.sol";
import {Constants} from "./utils/Constants.sol";
import {Pool} from "../../contracts/libraries/Pool.sol";

contract TickTestTest is Test {
    TickTest tick;

    enum FeeAmount {
        LOW,
        MEDIUM,
        HIGH
    }

    uint24[3] TICK_SPACINGS = [uint24(10), 60, 200];

    function setUp() public {
        tick = new TickTest();
    }

    function getMinTick(uint24 tickSpacing) internal pure returns (uint256) {
        return 0;
        // return (-887272 / tickSpacing) * tickSpacing; // ceil
    }

    function getMaxTick(uint24 tickSpacing) internal pure returns (uint256) {
        return uint256((87272 / tickSpacing) * tickSpacing);
    }

    function checkCantOverflow(uint24 tickSpacing, uint128 maxLiquidityPerTick) internal {
        assertLe(
            maxLiquidityPerTick * ((getMaxTick(tickSpacing) - getMinTick(tickSpacing)) / tickSpacing + 1),
            Constants.MAX_UINT128
        );
    }

    // #tickSpacingToMaxLiquidityPerTick
    function test_tickSpacingToMaxLiquidityPerTick_returnsTheCorrectValueForLowFeeTickSpacing() public {
        uint24 tickSpacing = TICK_SPACINGS[uint256(FeeAmount.LOW)];

        uint128 maxLiquidityPerTick = tick.tickSpacingToMaxLiquidityPerTick(int24(tickSpacing));

        assertEq(maxLiquidityPerTick, 1917565579412846627735051215301243);
        checkCantOverflow(TICK_SPACINGS[uint256(FeeAmount.LOW)], maxLiquidityPerTick);
    }

    function test_tickSpacingToMaxLiquidityPerTick_returnsTheCorrectValueForMediumFeeTickSpacing() public {
        uint24 tickSpacing = TICK_SPACINGS[uint256(FeeAmount.MEDIUM)];

        uint128 maxLiquidityPerTick = tick.tickSpacingToMaxLiquidityPerTick(int24(tickSpacing));

        assertEq(maxLiquidityPerTick, 11505069308564788430434325881101413); // 113.1 bits
        checkCantOverflow(TICK_SPACINGS[uint256(FeeAmount.LOW)], maxLiquidityPerTick);
    }

    function test_tickSpacingToMaxLiquidityPerTick_returnsTheCorrectValueForHighFeeTickSpacing() public {
        uint24 tickSpacing = TICK_SPACINGS[uint256(FeeAmount.HIGH)];

        uint128 maxLiquidityPerTick = tick.tickSpacingToMaxLiquidityPerTick(int24(tickSpacing));

        assertEq(maxLiquidityPerTick, 38347205785278154309959589375342946); // 114.7 bits
        checkCantOverflow(TICK_SPACINGS[uint256(FeeAmount.LOW)], maxLiquidityPerTick);
    }

    function test_tickSpacingToMaxLiquidityPerTick_returnsTheCorrectValueFor1() public {
        uint128 maxLiquidityPerTick = tick.tickSpacingToMaxLiquidityPerTick(1);

        assertEq(maxLiquidityPerTick, 191757530477355301479181766273477); // 126 bits
        checkCantOverflow(1, maxLiquidityPerTick);
    }

    function test_tickSpacingToMaxLiquidityPerTick_returnsTheCorrectValueForEntireRange() public {
        uint128 maxLiquidityPerTick = tick.tickSpacingToMaxLiquidityPerTick(887272);

        assertEq(maxLiquidityPerTick, Constants.MAX_UINT128 / 3); // 126 bits
        checkCantOverflow(887272, maxLiquidityPerTick);
    }

    function test_tickSpacingToMaxLiquidityPerTick_returnsTheCorrectValueFor2302() public {
        uint128 maxLiquidityPerTick = tick.tickSpacingToMaxLiquidityPerTick(2302);

        assertEq(maxLiquidityPerTick, 440854192570431170114173285871668350); // 118 bits
        checkCantOverflow(2302, maxLiquidityPerTick);
    }

    function test_tickSpacingToMaxLiquidityPerTick_gasCostMinTickSpacing() public {
        uint256 gasCost = tick.getGasCostOfTickSpacingToMaxLiquidityPerTick(1);

        assertGt(gasCost, 0);
    }

    function test_tickSpacingToMaxLiquidityPerTick_gasCost60TickSpacing() public {
        uint256 gasCost = tick.getGasCostOfTickSpacingToMaxLiquidityPerTick(60);

        assertGt(gasCost, 0);
    }

    function test_tickSpacingToMaxLiquidityPerTick_gasCostMaxTickSpacing() public {
        int24 MAX_TICK_SPACING = 32767;
        uint256 gasCost = tick.getGasCostOfTickSpacingToMaxLiquidityPerTick(MAX_TICK_SPACING);

        assertGt(gasCost, 0);
    }

    // #getFeeGrowthInside
    function test_getFeeGrowthInside_returnsAllForTwoUninitializedTicksIfTickIsInside() public {
        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = tick.getFeeGrowthInside(-2, 2, 0, 15, 15);

        assertEq(feeGrowthInside0X128, 15);
        assertEq(feeGrowthInside1X128, 15);
    }

    function test_getFeeGrowthInside_returns0ForTwoUninitializedTicksIfTickIsAbove() public {
        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = tick.getFeeGrowthInside(-2, 2, 4, 15, 15);

        assertEq(feeGrowthInside0X128, 0);
        assertEq(feeGrowthInside1X128, 0);
    }

    function test_getFeeGrowthInside_returns0ForTwoUninitializedTicksIfTickIsBelow() public {
        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = tick.getFeeGrowthInside(-2, 2, -4, 15, 15);

        assertEq(feeGrowthInside0X128, 0);
        assertEq(feeGrowthInside1X128, 0);
    }

    function test_getFeeGrowthInside_subtractsUpperTickIfBelow() public {
        Pool.TickInfo memory info;

        info.feeGrowthOutside0X128 = 2;
        info.feeGrowthOutside1X128 = 3;
        info.liquidityGross = 0;
        info.liquidityNet = 0;

        tick.setTick(2, info);

        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = tick.getFeeGrowthInside(-2, 2, 0, 15, 15);

        assertEq(feeGrowthInside0X128, 13);
        assertEq(feeGrowthInside1X128, 12);
    }

    function test_getFeeGrowthInside_subtractsLowerTickIfAbove() public {
        Pool.TickInfo memory info;

        info.feeGrowthOutside0X128 = 2;
        info.feeGrowthOutside1X128 = 3;
        info.liquidityGross = 0;
        info.liquidityNet = 0;

        tick.setTick(-2, info);

        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = tick.getFeeGrowthInside(-2, 2, 0, 15, 15);

        assertEq(feeGrowthInside0X128, 13);
        assertEq(feeGrowthInside1X128, 12);
    }

    function test_getFeeGrowthInside_subtractsUpperAndLowerTickIfInside() public {
        Pool.TickInfo memory info;

        info.feeGrowthOutside0X128 = 2;
        info.feeGrowthOutside1X128 = 3;
        info.liquidityGross = 0;
        info.liquidityNet = 0;

        tick.setTick(-2, info);

        info.feeGrowthOutside0X128 = 4;
        info.feeGrowthOutside1X128 = 1;
        info.liquidityGross = 0;
        info.liquidityNet = 0;

        tick.setTick(2, info);

        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = tick.getFeeGrowthInside(-2, 2, 0, 15, 15);

        assertEq(feeGrowthInside0X128, 9);
        assertEq(feeGrowthInside1X128, 11);
    }

    function test_getFeeGrowthInside_worksCorrectlyWithOverflowOnInsideTick() public {
        Pool.TickInfo memory info;

        info.feeGrowthOutside0X128 = Constants.MAX_UINT256 - 3;
        info.feeGrowthOutside1X128 = Constants.MAX_UINT256 - 2;
        info.liquidityGross = 0;
        info.liquidityNet = 0;

        tick.setTick(-2, info);

        info.feeGrowthOutside0X128 = 3;
        info.feeGrowthOutside1X128 = 5;
        info.liquidityGross = 0;
        info.liquidityNet = 0;

        tick.setTick(2, info);

        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = tick.getFeeGrowthInside(-2, 2, 0, 15, 15);

        assertEq(feeGrowthInside0X128, 16);
        assertEq(feeGrowthInside1X128, 13);
    }

    // #update
    function test_update_flipsFromZeroToNonzero() public {
        (bool flipped, uint128 liquidityGrossAfter) = tick.update(0, 0, 1, 0, 0, false);

        assertEq(flipped, true);
        assertEq(liquidityGrossAfter, 1);
    }

    function test_update_doesNotFlipFromNonzeroToGreaterNonzero() public {
        tick.update(0, 0, 1, 0, 0, false);
        (bool flipped, uint128 liquidityGrossAfter) = tick.update(0, 0, 1, 0, 0, false);

        assertEq(flipped, false);
        assertEq(liquidityGrossAfter, 2);
    }

    function test_update_flipsFromNonzeroToZero() public {
        tick.update(0, 0, 1, 0, 0, false);
        (bool flipped, uint128 liquidityGrossAfter) = tick.update(0, 0, -1, 0, 0, false);

        assertEq(flipped, true);
        assertEq(liquidityGrossAfter, 0);
    }

    function test_update_doesNotFlipFromNonzeroToLesserZero() public {
        tick.update(0, 0, 2, 0, 0, false);
        (bool flipped, uint128 liquidityGrossAfter) = tick.update(0, 0, -1, 0, 0, false);

        assertEq(flipped, false);
        assertEq(liquidityGrossAfter, 1);
    }

    function test_update_netsTheLiquidityBasedOnUpperFlag() public {
        Pool.TickInfo memory tickInfo;

        tick.update(0, 0, 2, 0, 0, false);
        tick.update(0, 0, 1, 0, 0, true);
        tick.update(0, 0, 3, 0, 0, true);
        tick.update(0, 0, 1, 0, 0, false);
        tickInfo = tick.ticks(0);

        assertEq(tickInfo.liquidityGross, 2 + 1 + 3 + 1);
        assertEq(tickInfo.liquidityNet, 2 - 1 - 3 + 1);
    }

    function test_update_revertsOnOverflowLiquidityGross() public {
        tick.update(0, 0, int128(Constants.MAX_UINT128 / 2 - 1), 0, 0, false);

        vm.expectRevert();
        tick.update(0, 0, int128(Constants.MAX_UINT128 / 2 - 1), 0, 0, false);
    }

    function test_update_assumesAllGrowthHappensBelowTicksLteCurrentTick() public {
        Pool.TickInfo memory tickInfo;

        tick.update(1, 1, 1, 1, 2, false);
        tickInfo = tick.ticks(1);

        assertEq(tickInfo.feeGrowthOutside0X128, 1);
        assertEq(tickInfo.feeGrowthOutside1X128, 2);
    }

    function test_update_doesNotSetAnyGrowthFieldsIfTickIsAlreadyInitialized() public {
        Pool.TickInfo memory tickInfo;

        tick.update(1, 1, 1, 1, 2, false);
        tick.update(1, 1, 1, 6, 7, false);
        tickInfo = tick.ticks(1);

        assertEq(tickInfo.feeGrowthOutside0X128, 1);
        assertEq(tickInfo.feeGrowthOutside1X128, 2);
    }

    function test_update_doesNotSetAnyGrowthFieldsForTicksGtCurrentTick() public {
        Pool.TickInfo memory tickInfo;

        tick.update(2, 1, 1, 1, 2, false);
        tickInfo = tick.ticks(2);

        assertEq(tickInfo.feeGrowthOutside0X128, 0);
        assertEq(tickInfo.feeGrowthOutside1X128, 0);
    }

    // #update liquidity parsing
    function test_update_liquidityParsingParsesMaxUint128StoredLiquidityGrossBeforeUpdate() public {
        Pool.TickInfo memory info;

        info.feeGrowthOutside0X128 = 0;
        info.feeGrowthOutside1X128 = 0;
        info.liquidityGross = Constants.MAX_UINT128;
        info.liquidityNet = 0;

        tick.setTick(2, info);
        tick.update(2, 1, -1, 1, 2, false);

        info = tick.ticks(2);

        assertEq(info.liquidityGross, Constants.MAX_UINT128 - 1);
        assertEq(info.liquidityNet, -1);
    }

    function test_update_liquidityParsingParsesMaxUint128StoredLiquidityGrossAfterUpdate() public {
        Pool.TickInfo memory info;

        info.feeGrowthOutside0X128 = 0;
        info.feeGrowthOutside1X128 = 0;
        info.liquidityGross = (Constants.MAX_UINT128 / 2) + 1;
        info.liquidityNet = 0;

        tick.setTick(2, info);

        tick.update(2, 1, int128(Constants.MAX_UINT128 / 2), 1, 2, false);

        info = tick.ticks(2);

        assertEq(info.liquidityGross, Constants.MAX_UINT128);
        assertEq(info.liquidityNet, int128(Constants.MAX_UINT128 / 2));
    }

    function test_update_liquidityParsingParsesMaxInt128StoredLiquidityGrossBeforeUpdate() public {
        Pool.TickInfo memory info;

        info.feeGrowthOutside0X128 = 0;
        info.feeGrowthOutside1X128 = 0;
        info.liquidityGross = 1;
        info.liquidityNet = int128(Constants.MAX_UINT128 / 2);

        tick.setTick(2, info);
        tick.update(2, 1, -1, 1, 2, false);

        info = tick.ticks(2);

        assertEq(info.liquidityGross, 0);
        assertEq(info.liquidityNet, int128(Constants.MAX_UINT128 / 2 - 1));
    }

    function test_update_liquidityParsingParsesMaxInt128StoredLiquidityGrossAfterUpdate() public {
        Pool.TickInfo memory info;

        info.feeGrowthOutside0X128 = 0;
        info.feeGrowthOutside1X128 = 0;
        info.liquidityGross = 0;
        info.liquidityNet = int128(Constants.MAX_UINT128 / 2 - 1);

        tick.setTick(2, info);

        tick.update(2, 1, 1, 1, 2, false);

        info = tick.ticks(2);

        assertEq(info.liquidityGross, 1);
        assertEq(info.liquidityNet, int128(Constants.MAX_UINT128 / 2));
    }

    // #clear
    function test_clear_deletesAllTheDataInTheTick() public {
        Pool.TickInfo memory info;

        info.feeGrowthOutside0X128 = 1;
        info.feeGrowthOutside1X128 = 2;
        info.liquidityGross = 3;
        info.liquidityNet = 4;

        tick.setTick(2, info);

        tick.clear(2);

        info = tick.ticks(2);

        assertEq(info.feeGrowthOutside0X128, 0);
        assertEq(info.feeGrowthOutside1X128, 0);
        assertEq(info.liquidityGross, 0);
        assertEq(info.liquidityNet, 0);
    }

    // #cross
    function test_cross_flipsTheGrowthVariables() public {
        Pool.TickInfo memory info;

        info.feeGrowthOutside0X128 = 1;
        info.feeGrowthOutside1X128 = 2;
        info.liquidityGross = 3;
        info.liquidityNet = 4;

        tick.setTick(2, info);

        tick.cross(2, 7, 9);

        info = tick.ticks(2);

        assertEq(info.feeGrowthOutside0X128, 6);
        assertEq(info.feeGrowthOutside1X128, 7);
    }

    function test_cross_twoFlipsAreNoOp() public {
        Pool.TickInfo memory info;

        info.feeGrowthOutside0X128 = 1;
        info.feeGrowthOutside1X128 = 2;
        info.liquidityGross = 3;
        info.liquidityNet = 4;

        tick.setTick(2, info);

        tick.cross(2, 7, 9);
        tick.cross(2, 7, 9);

        info = tick.ticks(2);

        assertEq(info.feeGrowthOutside0X128, 1);
        assertEq(info.feeGrowthOutside1X128, 2);
    }
}
