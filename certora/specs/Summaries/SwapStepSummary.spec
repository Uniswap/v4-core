/// All of these methods are pure so a deterministic ghost function summary is a valid over-approximation by definition.

// A relatively accurate summarization of the SwapMath.computeSwapStep function. Is useful for both eliminating timeouts
// and proving meaningful rules about swap amounts (see Accounting_Swap.spec for example). Depending on the rules assertion,
// the summarizations might not be accurate enough and introduce spurious counter-examples. Then more axioms would be required.
// All of the axioms in this file are proven for the original function (while summarizing SqrtPriceMath library) in the SwapMathTest.spec.
methods {
    function SwapMath.getSqrtPriceTarget(
        bool zeroForOne, uint160 sqrtPriceNext, uint160 sqrtPriceLimitX96
    ) internal returns (uint160) => sqrtPriceTargetCVL(zeroForOne, sqrtPriceNext, sqrtPriceLimitX96);

    function SwapMath.computeSwapStep(
        uint160 sqrtPriceCurrentX96,
        uint160 sqrtPriceTargetX96,
        uint128 liquidity,
        int256 amountRemaining,
        uint24 feePips
    ) internal returns (uint160, uint256, uint256, uint256) 
    => computeSwapStepCVL(sqrtPriceCurrentX96, sqrtPriceTargetX96, liquidity, amountRemaining, feePips);
}

/// Based on SwapMath.t.sol / test_fuzz_getSqrtPriceTarget
function sqrtPriceTargetCVL(bool zeroForOne, uint160 sqrtPriceNextX96, uint160 sqrtPriceLimitX96) returns uint160 {
    return (zeroForOne ? sqrtPriceNextX96 < sqrtPriceLimitX96 : sqrtPriceNextX96 > sqrtPriceLimitX96)
            ? sqrtPriceLimitX96
            : sqrtPriceNextX96;
}

/// Track sum of tokens that are swapped through the swap iterations.
ghost mathint sumOfAmounts0;
ghost mathint sumOfAmounts1;

/*
Pa = sqrtPriceCurrentX96
Pb = sqrtPriceTargetX96
L = liquidity
z = amountRemaining
fee = feePips
*/
function computeSwapStepCVL(uint160 Pa, uint160 Pb, uint128 L, int256 z, uint24 fee) returns (uint160,uint256,uint256,uint256) {
    bool zeroForOne = Pa >= Pb;
    bool exactIn = z < 0;

    uint160 Pnext = swapStep_nextSqrtPrice(Pa, Pb, L, z, fee);
    sumOfAmounts0 = sumOfAmounts0 + amount0Delta(Pa, Pnext, L, true);
    sumOfAmounts1 = sumOfAmounts1 + amount1Delta(Pa, Pnext, L, true);

    return (
        Pnext,
        swapStep_amountIn(Pa, Pb, L, z, fee),
        swapStep_amountOut(Pa, Pb, L, z, fee),
        swapStep_feeAmount(Pa, Pb, L, z, fee)
    );
}

persistent ghost swapStep_nextSqrtPrice(uint160,uint160,uint128,int256,uint24) returns uint160 {
    axiom 
        forall uint160 sqrtP. /// sqrtPriceCurrentX96
        forall uint160 sqrtQ. /// sqrtPriceTargetX96
        forall uint128 liquidity.
        forall int256 amount.
        forall uint24 feePips.
        /// The next price never exceeds the price limit (sqrtQ).
        /// zeroForOne
        sqrtP >= sqrtQ ? (
            swapStep_nextSqrtPrice(sqrtP, sqrtQ, liquidity, amount, feePips) <= sqrtP &&
            swapStep_nextSqrtPrice(sqrtP, sqrtQ, liquidity, amount, feePips) >= sqrtQ
        ) : (
            swapStep_nextSqrtPrice(sqrtP, sqrtQ, liquidity, amount, feePips) >= sqrtP &&
            swapStep_nextSqrtPrice(sqrtP, sqrtQ, liquidity, amount, feePips) <= sqrtQ
        );
}

persistent ghost swapStep_amountIn(uint160,uint160,uint128,int256,uint24) returns uint256 {
    axiom 
        forall uint160 sqrtP. /// sqrtPriceCurrentX96
        forall uint160 sqrtQ. /// sqrtPriceTargetX96
        forall uint128 liquidity.
        forall int256 amount.
        forall uint24 feePips.
        /// zeroForOne
        sqrtP >= sqrtQ ? (
            swapStep_amountIn(sqrtP, sqrtQ, liquidity, amount, feePips)
                >= amount0Delta(swapStep_nextSqrtPrice(sqrtP, sqrtQ, liquidity, amount, feePips), sqrtP, liquidity, true)
        ) : (
            swapStep_amountIn(sqrtP, sqrtQ, liquidity, amount, feePips)
                >= amount1Delta(swapStep_nextSqrtPrice(sqrtP, sqrtQ, liquidity, amount, feePips), sqrtP, liquidity, true)
        );
}

persistent ghost swapStep_amountOut(uint160,uint160,uint128,int256,uint24) returns uint256 {
    axiom 
        forall uint160 sqrtP. /// sqrtPriceCurrentX96
        forall uint160 sqrtQ. /// sqrtPriceTargetX96
        forall uint128 liquidity.
        forall int256 amount.
        forall uint24 feePips.
        /// zeroForOne
        sqrtP >= sqrtQ ? (
            swapStep_amountOut(sqrtP, sqrtQ, liquidity, amount, feePips)
                <= amount1Delta(swapStep_nextSqrtPrice(sqrtP, sqrtQ, liquidity, amount, feePips), sqrtP, liquidity, false)
        ) : (
            swapStep_amountOut(sqrtP, sqrtQ, liquidity, amount, feePips)
                <= amount0Delta(swapStep_nextSqrtPrice(sqrtP, sqrtQ, liquidity, amount, feePips), sqrtP, liquidity, false)
        );

    axiom 
        forall uint160 sqrtP. /// sqrtPriceCurrentX96
        forall uint160 sqrtQ. /// sqrtPriceTargetX96
        forall uint128 liquidity.
        forall int256 amount.
        forall uint24 feePips.
        /// !exactIn
        amount >=0 => to_mathint(amount) >= to_mathint(swapStep_amountOut(sqrtP, sqrtQ, liquidity, amount, feePips));
}

persistent ghost swapStep_feeAmount(uint160,uint160,uint128,int256,uint24) returns uint256 {
    axiom 
        forall uint160 sqrtP. /// sqrtPriceCurrentX96
        forall uint160 sqrtQ. /// sqrtPriceTargetX96
        forall uint128 liquidity.
        forall int256 amount.
        forall uint24 feePips.
        /// exactIn
        amount < 0 => amount 
        + swapStep_amountIn(sqrtP, sqrtQ, liquidity, amount, feePips)
        + swapStep_feeAmount(sqrtP, sqrtQ, liquidity, amount, feePips) <=0;
}
