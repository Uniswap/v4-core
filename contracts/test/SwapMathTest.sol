// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {SwapMath} from "../libraries/SwapMath.sol";
import {UQ64x96} from "../libraries/FixedPoint96.sol";

contract SwapMathTest {
    function computeSwapStep(
        uint160 sqrtPX96,
        uint160 sqrtPTargetX96,
        uint128 liquidity,
        int256 amountRemaining,
        uint24 feePips
    ) external pure returns (UQ64x96 sqrtQ, uint256 amountIn, uint256 amountOut, uint256 feeAmount) {
        UQ64x96 sqrtP = UQ64x96.wrap(sqrtPX96);
        UQ64x96 sqrtPTarget = UQ64x96.wrap(sqrtPTargetX96);
        return SwapMath.computeSwapStep(sqrtP, sqrtPTarget, liquidity, amountRemaining, feePips);
    }

    function getGasCostOfComputeSwapStep(
        uint160 sqrtPX96,
        uint160 sqrtPTargetX96,
        uint128 liquidity,
        int256 amountRemaining,
        uint24 feePips
    ) external view returns (uint256) {
        UQ64x96 sqrtP = UQ64x96.wrap(sqrtPX96);
        UQ64x96 sqrtPTarget = UQ64x96.wrap(sqrtPTargetX96);
        uint256 gasBefore = gasleft();
        SwapMath.computeSwapStep(sqrtP, sqrtPTarget, liquidity, amountRemaining, feePips);
        return gasBefore - gasleft();
    }
}
