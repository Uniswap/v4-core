import "../Common/TickMathDefinitions.spec";

/// All of these methods are pure so a deterministic ghost function summary is a valid over-approximation by definition.

// A relatively accurate summarization of the SqrtPriceMath library functions. Is useful for both eliminating timeouts
// and proving meaningful rules about swap amounts (see Accounting_Swap.spec for example). Depending on the rules assertion,
// the summarizations might not be accurate enough and introduce spurious counter-examples. Then more axioms would be required.
// All of the axioms in this file are proven for the original function (while summarizing TickMath library) in the SqrtPriceMathTest.spec.
methods {
    function SqrtPriceMath.getNextSqrtPriceFromInput(
        uint160 sqrtPX96, uint128 liquidity, uint256 amountIn, bool zeroForOne
    ) internal returns (uint160) => nextSqrtPriceFromInput(sqrtPX96,liquidity,amountIn,zeroForOne);

    function SqrtPriceMath.getNextSqrtPriceFromOutput(
        uint160 sqrtPX96, uint128 liquidity, uint256 amountOut, bool zeroForOne
    ) internal returns (uint160) => nextSqrtPriceFromOutput(sqrtPX96,liquidity,amountOut,zeroForOne);

    function SqrtPriceMath.getAmount0Delta(
        uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint128 liquidity, bool roundUp
    ) internal returns (uint256) => amount0Delta(sqrtPriceAX96,sqrtPriceBX96,liquidity,roundUp);
    
    function SqrtPriceMath.getAmount1Delta(
        uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint128 liquidity, bool roundUp
    ) internal returns (uint256) => amount1Delta(sqrtPriceAX96,sqrtPriceBX96,liquidity,roundUp);
}

/// x is greater or equal to y by at most "diff".
definition GreaterUpTo(mathint x, mathint y, mathint diff) returns bool = x >= y && x - y <= diff;

/// Axioms are verified in SqrtPriceMathTest.spec
persistent ghost nextSqrtPriceFromInput(uint160,uint128,uint256,bool) returns uint160 {
    axiom forall uint160 sqrtP. forall uint128 liquidity. forall uint256 amountIn.
        isValidSqrt(sqrtP) =>
        /// zeroForOne = true
        nextSqrtPriceFromInput(sqrtP, liquidity, amountIn, true) <= sqrtP &&
        /// zeroForOne = false
        nextSqrtPriceFromInput(sqrtP, liquidity, amountIn, false) >= sqrtP;
}

persistent ghost nextSqrtPriceFromOutput(uint160,uint128,uint256,bool) returns uint160 {
    axiom forall uint160 sqrtP. forall uint128 liquidity. forall uint256 amountOut.
        isValidSqrt(sqrtP) =>
        /// zeroForOne = true
        nextSqrtPriceFromOutput(sqrtP, liquidity, amountOut, true) <= sqrtP &&
        /// zeroForOne = false
        nextSqrtPriceFromOutput(sqrtP, liquidity, amountOut, false) >= sqrtP;
}

persistent ghost amount0Delta(uint160,uint160,uint128,bool) returns uint256 
{
    axiom forall uint160 sqrtP. forall uint128 liquidity. forall uint256 amount.
    (isValidSqrt(sqrtP) =>
        amount0Delta(
            sqrtP, 
            nextSqrtPriceFromOutput(sqrtP, liquidity, amount, false), 
            liquidity,
            false
        ) >= amount
    ) 
    &&
    (isValidSqrt(sqrtP) =>
        amount0Delta(
            nextSqrtPriceFromInput(sqrtP, liquidity, amount, true), 
            sqrtP, 
            liquidity,
            true
        ) <= amount
    );

    axiom forall uint160 sqrtP. forall uint160 sqrtQ. forall uint128 liquidity. forall bool roundUp.
        /// Zero
        ((sqrtP == sqrtQ || liquidity == 0) => 
        amount0Delta(sqrtP, sqrtQ, liquidity, roundUp) == 0) &&
        /// Symmetry
        amount0Delta(sqrtP, sqrtQ, liquidity, roundUp) == amount0Delta(sqrtQ, sqrtP, liquidity, roundUp) &&
        /// Rounding difference
        GreaterUpTo(amount0Delta(sqrtP, sqrtQ, liquidity, true), amount0Delta(sqrtP, sqrtQ, liquidity, false), 1);

    axiom forall uint128 liquidity. forall uint160 sqrtP. forall uint160 sqrtQ. forall uint160 sqrtR.
        // Additivity:
        (sqrtP <= sqrtQ && sqrtQ <= sqrtR && isValidSqrt(sqrtP) && isValidSqrt(sqrtR)) => (
            GreaterUpTo(
                amount0Delta(sqrtP, sqrtQ, liquidity, true) + 
                amount0Delta(sqrtQ, sqrtR, liquidity, true),
                to_mathint(amount0Delta(sqrtP, sqrtR, liquidity, true)),
                1
            )
            &&
            GreaterUpTo(
                to_mathint(amount0Delta(sqrtP, sqrtR, liquidity, false)),
                amount0Delta(sqrtP, sqrtQ, liquidity, false) + 
                amount0Delta(sqrtQ, sqrtR, liquidity, false),
                1
            )
        );

    axiom forall uint128 liquidityA. forall uint128 liquidityB.
        forall uint160 sqrtP. forall uint160 sqrtQ.
        /// Monotonicity
        (liquidityA < liquidityB && isValidSqrt(sqrtP) && isValidSqrt(sqrtQ)) =>
        amount0Delta(sqrtP, sqrtQ, liquidityA, true) <= amount0Delta(sqrtP, sqrtQ, liquidityB, true) 
        &&
        amount0Delta(sqrtP, sqrtQ, liquidityA, false) <= amount0Delta(sqrtP, sqrtQ, liquidityB, false);

    axiom forall uint128 liquidityA. forall uint128 liquidityB. forall uint128 liquidityC.
        forall uint160 sqrtP. forall uint160 sqrtQ.
        /// Additivity:
        (liquidityA + liquidityB == to_mathint(liquidityC) && isValidSqrt(sqrtP) && isValidSqrt(sqrtQ)) => (
            GreaterUpTo(
                amount0Delta(sqrtP, sqrtQ, liquidityA, true) + 
                amount0Delta(sqrtP, sqrtQ, liquidityB, true),
                to_mathint(amount0Delta(sqrtP, sqrtQ, liquidityC, true)),
                1
            )
            &&
            GreaterUpTo(   
                to_mathint(amount0Delta(sqrtP, sqrtQ, liquidityC, false)),
                amount0Delta(sqrtP, sqrtQ, liquidityA, false) + 
                amount0Delta(sqrtP, sqrtQ, liquidityB, false),
                1
            )
        );
}

persistent ghost amount1Delta(uint160,uint160,uint128,bool) returns uint256 
{
    axiom forall uint160 sqrtP. forall uint128 liquidity. forall uint256 amount.
        (isValidSqrt(sqrtP) => 
        amount1Delta(
            sqrtP, 
            nextSqrtPriceFromOutput(sqrtP, liquidity, amount, true), 
            liquidity,
            false
        ) >= amount)
        &&
        (isValidSqrt(sqrtP) =>
        amount1Delta(
            nextSqrtPriceFromInput(sqrtP, liquidity, amount, false) , 
            sqrtP, 
            liquidity,
            true
        ) <= amount);

    axiom forall uint160 sqrtP. forall uint160 sqrtQ. forall uint128 liquidity. forall bool roundUp.
        /// Zero
        ((sqrtP == sqrtQ || liquidity == 0) => 
        amount1Delta(sqrtP, sqrtQ, liquidity, roundUp) == 0) &&
        /// Symmetry
        amount1Delta(sqrtP, sqrtQ, liquidity, roundUp) == amount1Delta(sqrtQ, sqrtP, liquidity, roundUp) &&
        /// Rounding difference
        GreaterUpTo(amount1Delta(sqrtP, sqrtQ, liquidity, true), amount1Delta(sqrtP, sqrtQ, liquidity, false), 1);

    axiom forall uint128 liquidity. forall uint160 sqrtP. forall uint160 sqrtQ. forall uint160 sqrtR.
        // Additivity:
        (sqrtP <= sqrtQ && sqrtQ <= sqrtR && isValidSqrt(sqrtP) && isValidSqrt(sqrtR)) => (
            GreaterUpTo(
                amount1Delta(sqrtP, sqrtQ, liquidity, true) + 
                amount1Delta(sqrtQ, sqrtR, liquidity, true),
                to_mathint(amount1Delta(sqrtP, sqrtR, liquidity, true)),
                1
            )
            &&
            GreaterUpTo(
                to_mathint(amount1Delta(sqrtP, sqrtR, liquidity, false)),
                amount1Delta(sqrtP, sqrtQ, liquidity, false) + 
                amount1Delta(sqrtQ, sqrtR, liquidity, false),
                1
            )
        );

    axiom forall uint128 liquidityA. forall uint128 liquidityB.
        forall uint160 sqrtP. forall uint160 sqrtQ.
        /// Monotonicity
        (liquidityA < liquidityB && isValidSqrt(sqrtP) && isValidSqrt(sqrtQ)) =>
        amount1Delta(sqrtP, sqrtQ, liquidityA, true) <= amount1Delta(sqrtP, sqrtQ, liquidityB, true) 
        &&
        amount1Delta(sqrtP, sqrtQ, liquidityA, false) <= amount1Delta(sqrtP, sqrtQ, liquidityB, false);

    axiom forall uint128 liquidityA. forall uint128 liquidityB. forall uint128 liquidityC.
        forall uint160 sqrtP. forall uint160 sqrtQ.
        /// Additivity:
        (liquidityA + liquidityB == to_mathint(liquidityC) && isValidSqrt(sqrtP) && isValidSqrt(sqrtQ)) => (
            GreaterUpTo(
                amount1Delta(sqrtP, sqrtQ, liquidityA, true) + 
                amount1Delta(sqrtP, sqrtQ, liquidityB, true),
                to_mathint(amount1Delta(sqrtP, sqrtQ, liquidityC, true)),
                1
            )
            &&
            GreaterUpTo(   
                to_mathint(amount1Delta(sqrtP, sqrtQ, liquidityC, false)),
                amount1Delta(sqrtP, sqrtQ, liquidityA, false) + 
                amount1Delta(sqrtP, sqrtQ, liquidityB, false),
                1
            )
        );
}
