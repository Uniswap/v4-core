// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import { SwapMath } from "src/libraries/SwapMath.sol";
import { TickMath } from "src/libraries/TickMath.sol";

contract SwapMathTest {
    function computeSwapStep(
        uint160 sqrtPriceCurrentX96,
        uint160 sqrtPriceTargetX96,
        uint128 liquidity,
        int256 amountRemaining,
        uint24 feePips
    ) external pure returns (uint160 sqrtPriceNextX96, uint256 amountIn, uint256 amountOut, uint256 feeAmount)
    {
        return SwapMath.computeSwapStep(sqrtPriceCurrentX96, sqrtPriceTargetX96, liquidity, amountRemaining, feePips);
    }

    function getSqrtPriceTarget(
        bool zeroForOne, 
        uint160 sqrtPriceNextX96, 
        uint160 sqrtPriceLimitX96
    ) external pure returns (uint160 sqrtPriceTargetX96)
    {
        return SwapMath.getSqrtPriceTarget(zeroForOne, sqrtPriceNextX96, sqrtPriceLimitX96);
    }

    function MAX_SWAP_FEE() public pure returns (uint256) 
    {
        return SwapMath.MAX_SWAP_FEE;
    }

}