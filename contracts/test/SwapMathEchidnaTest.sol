// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {SwapMath} from "../libraries/SwapMath.sol";
import {UQ64x96} from "../libraries/FixedPoint96.sol";

contract SwapMathEchidnaTest {
    function checkComputeSwapStepInvariants(
        uint160 sqrtPriceRawX96,
        uint160 sqrtPriceTargetRawX96,
        uint128 liquidity,
        int256 amountRemaining,
        uint24 feePips
    ) external pure {
        require(sqrtPriceRawX96 > 0);
        require(sqrtPriceTargetRawX96 > 0);
        require(feePips > 0);
        require(feePips < 1e6);

        UQ64x96 sqrtPriceRaw = UQ64x96.wrap(sqrtPriceRawX96);
        UQ64x96 sqrtPriceTargetRaw = UQ64x96.wrap(sqrtPriceTargetRawX96);

        (UQ64x96 sqrtQ, uint256 amountIn, uint256 amountOut, uint256 feeAmount) =
            SwapMath.computeSwapStep(sqrtPriceRaw, sqrtPriceTargetRaw, liquidity, amountRemaining, feePips);

        assert(amountIn <= type(uint256).max - feeAmount);

        if (amountRemaining < 0) {
            assert(amountOut <= uint256(-amountRemaining));
        } else {
            assert(amountIn + feeAmount <= uint256(amountRemaining));
        }

        if (sqrtPriceRaw == sqrtPriceTargetRaw) {
            assert(amountIn == 0);
            assert(amountOut == 0);
            assert(feeAmount == 0);
            assert(sqrtQ == sqrtPriceTargetRaw);
        }

        // didn't reach price target, entire amount must be consumed
        if (sqrtQ != sqrtPriceTargetRaw) {
            if (amountRemaining < 0) assert(amountOut == uint256(-amountRemaining));
            else assert(amountIn + feeAmount == uint256(amountRemaining));
        }

        // next price is between price and price target
        if (sqrtPriceTargetRaw <= sqrtPriceRaw) {
            assert(sqrtQ <= sqrtPriceRaw);
            assert(sqrtQ >= sqrtPriceTargetRaw);
        } else {
            assert(sqrtQ >= sqrtPriceRaw);
            assert(sqrtQ <= sqrtPriceTargetRaw);
        }
    }
}
