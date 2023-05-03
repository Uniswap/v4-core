// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {TickMath} from "../libraries/TickMath.sol";
import {Q96} from "../libraries/FixedPoint96.sol";

contract TickMathTest {
    function getSqrtRatioAtTick(int24 tick) external pure returns (uint160) {
        return Q96.unwrap(TickMath.getSqrtRatioAtTick(tick));
    }

    function getGasCostOfGetSqrtRatioAtTick(int24 tick) external view returns (uint256) {
        uint256 gasBefore = gasleft();
        TickMath.getSqrtRatioAtTick(tick);
        return gasBefore - gasleft();
    }

    function getTickAtSqrtRatio(uint160 sqrtPriceX96) external pure returns (int24) {
        Q96 sqrtPrice = Q96.wrap(sqrtPriceX96);
        return TickMath.getTickAtSqrtRatio(sqrtPrice);
    }

    function getGasCostOfGetTickAtSqrtRatio(uint160 sqrtPriceX96) external view returns (uint256) {
        Q96 sqrtPrice = Q96.wrap(sqrtPriceX96);
        uint256 gasBefore = gasleft();
        TickMath.getTickAtSqrtRatio(sqrtPrice);
        return gasBefore - gasleft();
    }

    function MIN_SQRT_RATIO() external pure returns (uint160) {
        return Q96.unwrap(TickMath.MIN_SQRT_RATIO);
    }

    function MAX_SQRT_RATIO() external pure returns (uint160) {
        return Q96.unwrap(TickMath.MAX_SQRT_RATIO);
    }

    function MIN_TICK() external pure returns (int24) {
        return TickMath.MIN_TICK;
    }

    function MAX_TICK() external pure returns (int24) {
        return TickMath.MAX_TICK;
    }
}
