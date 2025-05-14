/// All of these methods are pure so a deterministic ghost function summary is a valid over-approximation by definition.

// A minimal deterministic summary for the `SwapMath.computeSwapStep` function.
// The function values aren't restricted in any way but are guaranteed to behave deterministically.
// Use this summarization for rules that do not concern swap amounts, and only concern general assertions.
methods {
    function SwapMath.computeSwapStep(
        uint160 sqrtPriceCurrentX96,
        uint160 sqrtPriceTargetX96,
        uint128 liquidity,
        int256 amountRemaining,
        uint24 feePips
    ) internal returns (uint160, uint256, uint256, uint256) 
    => computeSwapStepCVL(sqrtPriceCurrentX96, sqrtPriceTargetX96, liquidity, amountRemaining, feePips);

    function SwapMath.getSqrtPriceTarget(
        bool zeroForOne, uint160 sqrtPriceNext, uint160 sqrtPriceLimitX96
    ) internal returns (uint160) => sqrtPriceTargetCVL(zeroForOne, sqrtPriceNext, sqrtPriceLimitX96);
}

function sqrtPriceTargetCVL(bool zeroForOne, uint160 sqrtPriceNextX96, uint160 sqrtPriceLimitX96) returns uint160 {
    return (zeroForOne ? sqrtPriceNextX96 < sqrtPriceLimitX96 : sqrtPriceNextX96 > sqrtPriceLimitX96)
            ? sqrtPriceLimitX96
            : sqrtPriceNextX96;
}

function computeSwapStepCVL(uint160 Pa, uint160 Pb, uint128 L, int256 z, uint24 fee) returns (uint160,uint256,uint256,uint256) {
    return (
        swapStep_nextSqrtPrice(Pa, Pb, L, z, fee),
        swapStep_amountIn(Pa, Pb, L, z, fee),
        swapStep_amountOut(Pa, Pb, L, z, fee),
        swapStep_feeAmount(Pa, Pb, L, z, fee)
    );
}

persistent ghost swapStep_nextSqrtPrice(uint160,uint160,uint128,int256,uint24) returns uint160;
persistent ghost swapStep_amountIn(uint160,uint160,uint128,int256,uint24) returns uint256;
persistent ghost swapStep_amountOut(uint160,uint160,uint128,int256,uint24) returns uint256;
persistent ghost swapStep_feeAmount(uint160,uint160,uint128,int256,uint24) returns uint256;