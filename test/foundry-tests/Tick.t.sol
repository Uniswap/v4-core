// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {TickTest} from "../../contracts/test/TickTest.sol";
import {Constants} from "./utils/Constants.sol";

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
}
