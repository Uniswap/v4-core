import "../Summaries/TickMathSummary.spec";
import "../Summaries/FullMathSummary.spec";
import "../Summaries/UnsafeMathSummary.spec";
import "../Summaries/SqrtPriceMathRealSummary.spec";

using SwapMathTest as test;

methods {
    function test.getSqrtPriceTarget(bool,uint160,uint160) external returns (uint160) envfree;
    function test.computeSwapStep(uint160,uint160,uint128,int256,uint24) external returns (uint160, uint256, uint256, uint256) envfree;
    function test.MAX_SWAP_FEE() external returns (uint256) envfree;
}

/// Test assumptions are justified in code:
/*
    From Pool.sol:
    // a swap fee totaling MAX_SWAP_FEE (100%) makes exact output swaps impossible since the input is entirely consumed by the fee
        if (swapFee >= SwapMath.MAX_SWAP_FEE) {
            // if exactOutput
            if (params.amountSpecified > 0) {
                InvalidFeeForExactOut.selector.revertWith();
            }
        }

    //

    // swapFee is the pool's fee in pips (LP fee + protocol fee)
    // when the amount swapped is 0, there is no protocolFee applied and the fee amount paid to the protocol is set to 0
    if (params.amountSpecified == 0) return (BalanceDeltaLibrary.ZERO_DELTA, 0, swapFee, result);

    // amount cannot be zero, code returns early.
*/
function testAssumptions(uint24 feePips, int256 amount) {
    /// Based on Pool.sol
    require amount >= 0 => feePips < test.MAX_SWAP_FEE();
    /// Based on ValidSwapFee invariant.
    require feePips <= test.MAX_SWAP_FEE();
}

function applyNextSqrtPriceAxioms(uint160 sqrtP, uint160 sqrtQ, uint128 liquidity) {
    bool zeroForOne = sqrtP >= sqrtQ;

    if (zeroForOne) {
        require forall uint256 amount.
            (
                amount <= amount1Delta(sqrtQ, sqrtP, liquidity, false) =>
                sqrtQ <= nextSqrtPriceFromOutput(sqrtP, liquidity, amount, zeroForOne) && 
                sqrtP >= nextSqrtPriceFromOutput(sqrtP, liquidity, amount, zeroForOne)
            ) && (
                amount < amount0Delta(sqrtQ, sqrtP, liquidity, true) =>
                sqrtQ <= nextSqrtPriceFromInput(sqrtP, liquidity, amount, zeroForOne) && 
                sqrtP >= nextSqrtPriceFromInput(sqrtP, liquidity, amount, zeroForOne)
            );
    } else {
        require forall uint256 amount.
            (
                amount <= amount0Delta(sqrtQ, sqrtP, liquidity, false) =>
                sqrtQ >= nextSqrtPriceFromOutput(sqrtP, liquidity, amount, zeroForOne) && 
                sqrtP <= nextSqrtPriceFromOutput(sqrtP, liquidity, amount, zeroForOne)
            ) && (
                amount < amount1Delta(sqrtQ, sqrtP, liquidity, true) =>
                sqrtQ >= nextSqrtPriceFromInput(sqrtP, liquidity, amount, zeroForOne) && 
                sqrtP <= nextSqrtPriceFromInput(sqrtP, liquidity, amount, zeroForOne)
            );
    }
}

/// @title Verifies the bounds of the next sqrt price after calling computeSwapStep().
rule nextSqrtPriceCorrectBound() {
    uint160 sqrtP; require isValidSqrt(sqrtP); /// sqrtPriceCurrentX96
    uint160 sqrtQ; require isValidSqrt(sqrtQ); /// sqrtPriceTargetX96
    uint128 liquidity;
    int256 amount;
    uint24 feePips;
    testAssumptions(feePips, amount);
    applyNextSqrtPriceAxioms(sqrtP, sqrtQ, liquidity);

    uint160 sqrtPriceNextX96;
    uint256 amountIn;
    uint256 amountOut;
    uint256 feeAmount;

    sqrtPriceNextX96, amountIn, amountOut, feeAmount = 
        test.computeSwapStep(sqrtP, sqrtQ, liquidity, amount, feePips);

    assert sqrtP >= sqrtQ
        ? (sqrtPriceNextX96 <= sqrtP && sqrtPriceNextX96 >= sqrtQ)
        : (sqrtPriceNextX96 >= sqrtP && sqrtPriceNextX96 <= sqrtQ);
}

/// @title Verifies the bounds of the amountIn/amountOut after calling computeSwapStep().
rule swapCorrectBound() {
    uint160 sqrtP; require isValidSqrt(sqrtP); /// sqrtPriceCurrentX96
    uint160 sqrtQ; require isValidSqrt(sqrtQ); /// sqrtPriceTargetX96
    uint128 liquidity;
    int256 amount;
    uint24 feePips;
    testAssumptions(feePips, amount);
    
    bool zeroForOne = sqrtP >= sqrtQ;
    bool exactIn = amount < 0;

    uint160 sqrtPriceNextX96;
    uint256 amountIn;
    uint256 amountOut;
    uint256 feeAmount;

    sqrtPriceNextX96, amountIn, amountOut, feeAmount = 
        test.computeSwapStep(sqrtP, sqrtQ, liquidity, amount, feePips);

    if(zeroForOne) {
        assert amountOut <= amount1Delta(sqrtPriceNextX96, sqrtP, liquidity, false);
        assert amountIn >= amount0Delta(sqrtPriceNextX96, sqrtP, liquidity, true);
    } else {
        assert amountOut <= amount0Delta(sqrtPriceNextX96, sqrtP, liquidity, false);
        assert amountIn >= amount1Delta(sqrtPriceNextX96, sqrtP, liquidity, true);
    }
}

/// @title Verifies the bounds of fee amount and the extracted amount (amountOut) after calling computeSwapStep().
rule feeAmountCorrectBound() {
    uint160 sqrtP; require isValidSqrt(sqrtP); /// sqrtPriceCurrentX96
    uint160 sqrtQ; require isValidSqrt(sqrtQ); /// sqrtPriceTargetX96
    uint128 liquidity;
    int256 amount;
    uint24 feePips;
    testAssumptions(feePips, amount);
    
    bool zeroForOne = sqrtP >= sqrtQ;
    bool exactIn = amount < 0;

    uint160 sqrtPriceNextX96;
    uint256 amountIn;
    uint256 amountOut;
    uint256 feeAmount;

    sqrtPriceNextX96, amountIn, amountOut, feeAmount = 
        test.computeSwapStep(sqrtP, sqrtQ, liquidity, amount, feePips);

    if(!exactIn) {
        assert amount >= assert_int256(amountOut);
    } else {
        assert amount + amountIn + feeAmount <=0;
    }
}