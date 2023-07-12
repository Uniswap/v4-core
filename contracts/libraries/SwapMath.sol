// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {FullMath} from "./FullMath.sol";
import {SqrtPriceMath} from "./SqrtPriceMath.sol";
import {UQ64x96} from "./FixedPoint96.sol";

/// @title Computes the result of a swap within ticks
/// @notice Contains methods for computing the result of a swap within a single tick price range, i.e., a single tick.
library SwapMath {
    /// @notice Computes the result of swapping some amount in, or amount out, given the parameters of the swap
    /// @dev The fee, plus the amount in, will never exceed the amount remaining if the swap's `amountSpecified` is positive
    /// @param sqrtRatioCurrent The current sqrt price of the pool
    /// @param sqrtRatioTarget The price that cannot be exceeded, from which the direction of the swap is inferred
    /// @param liquidity The usable liquidity
    /// @param amountRemaining How much input or output amount is remaining to be swapped in/out
    /// @param feePips The fee taken from the input amount, expressed in hundredths of a bip
    /// @return sqrtRatioNext The price after swapping the amount in/out, not to exceed the price target
    /// @return amountIn The amount to be swapped in, of either currency0 or currency1, based on the direction of the swap
    /// @return amountOut The amount to be received, of either currency0 or currency1, based on the direction of the swap
    /// @return feeAmount The amount of input that will be taken as a fee
    function computeSwapStep(
        UQ64x96 sqrtRatioCurrent,
        UQ64x96 sqrtRatioTarget,
        uint128 liquidity,
        int256 amountRemaining,
        uint24 feePips
    ) internal pure returns (UQ64x96 sqrtRatioNext, uint256 amountIn, uint256 amountOut, uint256 feeAmount) {
        unchecked {
            bool zeroForOne = sqrtRatioCurrent >= sqrtRatioTarget;
            bool exactIn = amountRemaining >= 0;

            if (exactIn) {
                uint256 amountRemainingLessFee = FullMath.mulDiv(uint256(amountRemaining), 1e6 - feePips, 1e6);
                amountIn = zeroForOne
                    ? SqrtPriceMath.getAmount0Delta(sqrtRatioTarget, sqrtRatioCurrent, liquidity, true)
                    : SqrtPriceMath.getAmount1Delta(sqrtRatioCurrent, sqrtRatioTarget, liquidity, true);
                if (amountRemainingLessFee >= amountIn) {
                    sqrtRatioNext = sqrtRatioTarget;
                } else {
                    sqrtRatioNext = SqrtPriceMath.getNextSqrtPriceFromInput(
                        sqrtRatioCurrent, liquidity, amountRemainingLessFee, zeroForOne
                    );
                }
            } else {
                amountOut = zeroForOne
                    ? SqrtPriceMath.getAmount1Delta(sqrtRatioTarget, sqrtRatioCurrent, liquidity, false)
                    : SqrtPriceMath.getAmount0Delta(sqrtRatioCurrent, sqrtRatioTarget, liquidity, false);
                if (uint256(-amountRemaining) >= amountOut) {
                    sqrtRatioNext = sqrtRatioTarget;
                } else {
                    sqrtRatioNext = SqrtPriceMath.getNextSqrtPriceFromOutput(
                        sqrtRatioCurrent, liquidity, uint256(-amountRemaining), zeroForOne
                    );
                }
            }

            bool max = sqrtRatioTarget == sqrtRatioNext;

            // get the input/output amounts
            if (zeroForOne) {
                amountIn = max && exactIn
                    ? amountIn
                    : SqrtPriceMath.getAmount0Delta(sqrtRatioNext, sqrtRatioCurrent, liquidity, true);
                amountOut = max && !exactIn
                    ? amountOut
                    : SqrtPriceMath.getAmount1Delta(sqrtRatioNext, sqrtRatioCurrent, liquidity, false);
            } else {
                amountIn = max && exactIn
                    ? amountIn
                    : SqrtPriceMath.getAmount1Delta(sqrtRatioCurrent, sqrtRatioNext, liquidity, true);
                amountOut = max && !exactIn
                    ? amountOut
                    : SqrtPriceMath.getAmount0Delta(sqrtRatioCurrent, sqrtRatioNext, liquidity, false);
            }

            // cap the output amount to not exceed the remaining output amount
            if (!exactIn && amountOut > uint256(-amountRemaining)) {
                amountOut = uint256(-amountRemaining);
            }

            if (exactIn && sqrtRatioNext != sqrtRatioTarget) {
                // we didn't reach the target, so take the remainder of the maximum input as fee
                feeAmount = uint256(amountRemaining) - amountIn;
            } else {
                feeAmount = FullMath.mulDivRoundingUp(amountIn, feePips, 1e6 - feePips);
            }
        }
    }
}
