// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {UQ128x128} from "../libraries/FixedPoint128.sol";
import {Pool} from "../libraries/Pool.sol";

contract TickOverflowSafetyEchidnaTest {
    using Pool for Pool.State;

    int24 private constant MIN_TICK = -16;
    int24 private constant MAX_TICK = 16;

    Pool.State private pool;
    int24 private tick = 0;

    // half the cap of fee growth has happened, this can overflow
    UQ128x128 feeGrowthGlobal0 = UQ128x128.wrap(type(uint256).max / 2);
    UQ128x128 feeGrowthGlobal1 = UQ128x128.wrap(type(uint256).max / 2);

    // used to track how much total liquidity has been added. should never be negative
    int256 totalLiquidity = 0;
    // how much total growth has happened, this cannot overflow
    UQ128x128 private totalGrowth0 = UQ128x128.wrap(0);
    UQ128x128 private totalGrowth1 = UQ128x128.wrap(0);

    function increasefeeGrowthGlobal0(UQ128x128 amount) external {
        require(totalGrowth0 + amount > totalGrowth0); // overflow check
        feeGrowthGlobal0 = feeGrowthGlobal0 + amount; // overflow desired
        totalGrowth0 = totalGrowth0 + amount;
    }

    function increasefeeGrowthGlobal1(UQ128x128 amount) external {
        require(totalGrowth1 + amount > totalGrowth1); // overflow check
        feeGrowthGlobal1 = feeGrowthGlobal1 + amount; // overflow desired
        totalGrowth1 = totalGrowth1 + amount;
    }

    function setPosition(int24 tickLower, int24 tickUpper, int128 liquidityDelta) external {
        require(tickLower > MIN_TICK);
        require(tickUpper < MAX_TICK);
        require(tickLower < tickUpper);
        (bool flippedLower,) = pool.updateTick(tickLower, liquidityDelta, false);
        (bool flippedUpper,) = pool.updateTick(tickUpper, liquidityDelta, true);

        if (flippedLower) {
            if (liquidityDelta < 0) {
                assert(pool.ticks[tickLower].liquidityGross == 0);
                pool.clearTick(tickLower);
            } else {
                assert(pool.ticks[tickLower].liquidityGross > 0);
            }
        }

        if (flippedUpper) {
            if (liquidityDelta < 0) {
                assert(pool.ticks[tickUpper].liquidityGross == 0);
                pool.clearTick(tickUpper);
            } else {
                assert(pool.ticks[tickUpper].liquidityGross > 0);
            }
        }

        totalLiquidity += liquidityDelta;
        // requires should have prevented this
        assert(totalLiquidity >= 0);

        if (totalLiquidity == 0) {
            totalGrowth0 = UQ128x128.wrap(0);
            totalGrowth1 = UQ128x128.wrap(0);
        }
    }

    function moveToTick(int24 target) external {
        require(target > MIN_TICK);
        require(target < MAX_TICK);
        while (tick != target) {
            if (tick < target) {
                if (pool.ticks[tick + 1].liquidityGross > 0) {
                    pool.crossTick(tick + 1, feeGrowthGlobal0, feeGrowthGlobal1);
                }
                tick++;
            } else {
                if (pool.ticks[tick].liquidityGross > 0) {
                    pool.crossTick(tick, feeGrowthGlobal0, feeGrowthGlobal1);
                }
                tick--;
            }
        }
    }
}
