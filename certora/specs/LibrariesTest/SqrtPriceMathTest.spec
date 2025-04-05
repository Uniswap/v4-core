import "../Summaries/FullMathSummary.spec";
import "../Summaries/UnsafeMathSummary.spec";
import "../Common/TickMathDefinitions.spec";

using SqrtPriceMathTest as test;

methods {
    function test.getNextSqrtPriceFromInput(uint160, uint128, uint256, bool) external returns (uint160) envfree;
    function test.getNextSqrtPriceFromOutput(uint160, uint128, uint256, bool) external returns (uint160) envfree;
    function test.getAmount0Delta(uint160, uint160, uint128, bool) external returns (uint256) envfree;
    function test.getAmount1Delta(uint160, uint160, uint128, bool) external returns (uint256) envfree;
}

definition diffUpTo(mathint x, mathint y, mathint diff) returns bool = 
    x > y ? x - y <= diff : y - x <= diff;

rule getAmount0Delta_zero_diff(uint160 sqrtLower, uint160 sqrtUpper, uint128 liquidity, bool roundUp) {
    assert (sqrtLower == sqrtUpper || liquidity == 0) => 
        test.getAmount0Delta(sqrtLower, sqrtUpper, liquidity, roundUp) == 0;
}

rule getAmount0Delta_symmetric(uint160 sqrtLower, uint160 sqrtUpper, uint128 liquidity, bool roundUp) {
    assert test.getAmount0Delta(sqrtLower, sqrtUpper, liquidity, roundUp) ==
        test.getAmount0Delta(sqrtUpper, sqrtLower, liquidity, roundUp);
}

rule getAmount0Delta_rounding_diff(uint160 sqrtLower, uint160 sqrtUpper, uint128 liquidity) {
    mathint up_down_diff = 
        test.getAmount0Delta(sqrtLower, sqrtUpper, liquidity, true) - 
        test.getAmount0Delta(sqrtUpper, sqrtLower, liquidity, false);
    
    assert up_down_diff == 0 || up_down_diff == 1;
}

rule getAmount0Delta_liquidity_monotonic(uint160 sqrtLower, uint160 sqrtUpper, uint128 liquidityA, uint128 liquidityB, bool roundUp) {
    require isValidSqrt(sqrtLower);
    require isValidSqrt(sqrtUpper);
    uint256 amountA = test.getAmount0Delta(sqrtLower, sqrtUpper, liquidityA, roundUp);
    uint256 amountB = test.getAmount0Delta(sqrtLower, sqrtUpper, liquidityB, roundUp);
    assert liquidityA < liquidityB => amountA <= amountB;
}

rule getAmount0Delta_sqrtPrice_monotonic(uint160 sqrtA, uint160 sqrtB, uint160 sqrtC, uint128 liquidity, bool roundUp) {
    require isValidSqrt(sqrtA);
    require isValidSqrt(sqrtB);
    require isValidSqrt(sqrtC);
    uint256 amountB = test.getAmount0Delta(sqrtA, sqrtB, liquidity, roundUp);
    uint256 amountC = test.getAmount0Delta(sqrtA, sqrtC, liquidity, roundUp);
    assert (sqrtB < sqrtC && sqrtA <= sqrtB) => amountB <= amountC;
    assert (sqrtB < sqrtC && sqrtA >= sqrtC) => amountB >= amountC;
}

rule getAmount0Delta_sqrtPrice_additivity(uint160 sqrtA, uint160 sqrtB, uint160 sqrtC, uint128 liquidity, bool roundUp) {
    require isValidSqrt(sqrtA);
    require isValidSqrt(sqrtB);
    require isValidSqrt(sqrtC);
    /// Limiting case, otherwise, times-out.
    require sqrtA == MIN_SQRT_PRICE() && sqrtC == MAX_SQRT_PRICE();
    require sqrtA <= sqrtB && sqrtB <= sqrtC;

    uint256 amount1 = test.getAmount0Delta(sqrtA, sqrtB, liquidity, roundUp);
    uint256 amount2 = test.getAmount0Delta(sqrtB, sqrtC, liquidity, roundUp);
    uint256 amount3 = test.getAmount0Delta(sqrtA, sqrtC, liquidity, roundUp);

    assert roundUp => amount1 + amount2 >= amount3;
    assert !roundUp => amount1 + amount2 <= amount3;
    assert diffUpTo(amount1 + amount2, amount3, 1);
}

rule getAmount0Delta_liquidity_additivity(uint160 sqrtA, uint160 sqrtB, uint128 liquidityA, uint128 liquidityB, bool roundUp) {
    require isValidSqrt(sqrtA);
    require isValidSqrt(sqrtB);
    /// Limiting case, otherwise, times-out.
    require sqrtA == MIN_SQRT_PRICE() || sqrtB == MAX_SQRT_PRICE();
    
    uint128 liquidityC = require_uint128(liquidityA + liquidityB);
    uint256 amountA = test.getAmount0Delta(sqrtA, sqrtB, liquidityA, roundUp);
    uint256 amountB = test.getAmount0Delta(sqrtA, sqrtB, liquidityB, roundUp);
    uint256 amountC = test.getAmount0Delta(sqrtA, sqrtB, liquidityC, roundUp);

    assert roundUp => amountA + amountB >= amountC;
    assert !roundUp => amountA + amountB <= amountC;
    assert diffUpTo(amountA + amountB, amountC, 1);
}

rule getAmount1Delta_zero_diff(uint160 sqrtLower, uint160 sqrtUpper, uint128 liquidity, bool roundUp) {
    assert (sqrtLower == sqrtUpper || liquidity == 0) => 
        test.getAmount1Delta(sqrtLower, sqrtUpper, liquidity, roundUp) == 0;
}

rule getAmount1Delta_symmetric(uint160 sqrtLower, uint160 sqrtUpper, uint128 liquidity, bool roundUp) {
    assert test.getAmount1Delta(sqrtLower, sqrtUpper, liquidity, roundUp) ==
        test.getAmount1Delta(sqrtUpper, sqrtLower, liquidity, roundUp);
}

rule getAmount1Delta_rounding_diff(uint160 sqrtLower, uint160 sqrtUpper, uint128 liquidity) {
    mathint up_down_diff = 
        test.getAmount1Delta(sqrtLower, sqrtUpper, liquidity, true) - 
        test.getAmount1Delta(sqrtUpper, sqrtLower, liquidity, false);
    
    assert up_down_diff == 0 || up_down_diff == 1;
}

rule getAmount1Delta_sqrtPrice_monotonic(uint160 sqrtA, uint160 sqrtB, uint160 sqrtC, uint128 liquidity, bool roundUp) {
    require isValidSqrt(sqrtA);
    require isValidSqrt(sqrtB);
    require isValidSqrt(sqrtC);
    uint256 amountB = test.getAmount1Delta(sqrtA, sqrtB, liquidity, roundUp);
    uint256 amountC = test.getAmount1Delta(sqrtA, sqrtC, liquidity, roundUp);
    assert (sqrtB < sqrtC && sqrtA <= sqrtB) => amountB <= amountC;
    assert (sqrtB < sqrtC && sqrtA >= sqrtC) => amountB >= amountC;
}

rule getAmount1Delta_liquidity_monotonic(uint160 sqrtLower, uint160 sqrtUpper, uint128 liquidityA, uint128 liquidityB, bool roundUp) {
    require isValidSqrt(sqrtLower);
    require isValidSqrt(sqrtUpper);
    uint256 amountA = test.getAmount1Delta(sqrtLower, sqrtUpper, liquidityA, roundUp);
    uint256 amountB = test.getAmount1Delta(sqrtLower, sqrtUpper, liquidityB, roundUp);
    assert liquidityA < liquidityB => amountA <= amountB;
}

rule getAmount1Delta_sqrtPrice_additivity(uint160 sqrtA, uint160 sqrtB, uint160 sqrtC, uint128 liquidity, bool roundUp) {
    require isValidSqrt(sqrtA);
    require isValidSqrt(sqrtB);
    require isValidSqrt(sqrtC);
    require sqrtA <= sqrtB && sqrtB <= sqrtC;
    
    uint256 amount1 = test.getAmount1Delta(sqrtA, sqrtB, liquidity, roundUp);
    uint256 amount2 = test.getAmount1Delta(sqrtB, sqrtC, liquidity, roundUp);
    uint256 amount3 = test.getAmount1Delta(sqrtA, sqrtC, liquidity, roundUp);

    assert diffUpTo(amount1 + amount2, amount3, 1);
    assert roundUp => amount1 + amount2 >= amount3;
    assert !roundUp => amount1 + amount2 <= amount3;
}

rule getAmount1Delta_liquidity_additivity(uint160 sqrtA, uint160 sqrtB, uint128 liquidityA, uint128 liquidityB, bool roundUp) {
    require isValidSqrt(sqrtA);
    require isValidSqrt(sqrtB);
    
    uint128 liquidityC = require_uint128(liquidityA + liquidityB);
    uint256 amountA = test.getAmount1Delta(sqrtA, sqrtB, liquidityA, roundUp);
    uint256 amountB = test.getAmount1Delta(sqrtA, sqrtB, liquidityB, roundUp);
    uint256 amountC = test.getAmount1Delta(sqrtA, sqrtB, liquidityC, roundUp);

    assert diffUpTo(amountA + amountB, amountC, 1);
    assert roundUp => amountA + amountB >= amountC;
    assert !roundUp => amountA + amountB <= amountC;
}

rule amountDelta_getNextSqrtPriceFromInput_bound(uint160 sqrtP, uint160 sqrtQ, uint128 liquidity, uint256 amount) {
    require isValidSqrt(sqrtP);
    require isValidSqrt(sqrtQ);
    /// current price >= target price
    bool zeroForOne = sqrtP >= sqrtQ;

    uint256 amountIn;
    if(zeroForOne) {
        require amountIn == test.getAmount0Delta(sqrtQ, sqrtP, liquidity, true);
    } else {
        require amountIn == test.getAmount1Delta(sqrtP, sqrtQ, liquidity, true);
    }
    
    uint160 sqrtR = test.getNextSqrtPriceFromInput(sqrtP, liquidity, amount, zeroForOne);

    if (zeroForOne) {
        assert(amount < amountIn => sqrtQ <= sqrtR && sqrtR <= sqrtP);
    } else {
        assert(amount < amountIn => sqrtQ >= sqrtR && sqrtR >= sqrtP);
    }
}

rule amountDelta_getNextSqrtPriceFromOutput_bound(uint160 sqrtP, uint160 sqrtQ, uint128 liquidity, uint256 amount) {
    require isValidSqrt(sqrtP);
    require isValidSqrt(sqrtQ);
    /// current price >= target price
    bool zeroForOne = sqrtP >= sqrtQ;

    uint256 amountOut;
    if(zeroForOne) {
        require amountOut == test.getAmount1Delta(sqrtQ, sqrtP, liquidity, false);
    } else {
        require amountOut == test.getAmount0Delta(sqrtP, sqrtQ, liquidity, false);
    }
    
    uint160 sqrtR = test.getNextSqrtPriceFromOutput(sqrtP, liquidity, amount, zeroForOne);

    if (zeroForOne) {
        assert(amount <= amountOut => sqrtQ <= sqrtR && sqrtR <= sqrtP);
    } else {
        assert(amount <= amountOut => sqrtQ >= sqrtR && sqrtR >= sqrtP);
    }
}

rule getNextSqrtPriceFromInput_amountDelta_bound(uint160 sqrtP, uint128 liquidity, uint256 amountIn, bool zeroForOne) {
    require isValidSqrt(sqrtP);
    uint160 sqrtQ = test.getNextSqrtPriceFromInput(sqrtP, liquidity, amountIn, zeroForOne);

    if (zeroForOne) {
        assert(sqrtQ <= sqrtP);
        assert(amountIn >= test.getAmount0Delta(sqrtQ, sqrtP, liquidity, true));
        satisfy sqrtQ < sqrtP;
    } else {
        assert(sqrtQ >= sqrtP);
        assert(amountIn >= test.getAmount1Delta(sqrtP, sqrtQ, liquidity, true));
        satisfy sqrtQ > sqrtP;
    }
}

rule getNextSqrtPriceFromOutput_amountDelta_bound(uint160 sqrtP, uint128 liquidity, uint256 amountOut, bool zeroForOne) {
    require isValidSqrt(sqrtP);
    uint160 sqrtQ = test.getNextSqrtPriceFromOutput(sqrtP, liquidity, amountOut, zeroForOne);

    if (zeroForOne) {
        assert(sqrtQ <= sqrtP);
        assert(amountOut <= test.getAmount1Delta(sqrtQ, sqrtP, liquidity, false));
        satisfy sqrtQ < sqrtP;
    } else {
        assert(sqrtQ > 0); // this has to be true, otherwise we need another require
        assert(sqrtQ >= sqrtP);
        assert(amountOut <= test.getAmount0Delta(sqrtP, sqrtQ, liquidity, false));
        satisfy sqrtQ > sqrtP;
    }
}

function axiomA(uint160 sqrtP, uint128 liquidity, uint256 amountA, uint256 amountB) returns bool {
    return isValidSqrt(sqrtP) =>
        test.getAmount0Delta(
            sqrtP, 
            test.getNextSqrtPriceFromOutput(sqrtP, liquidity, amountA, false), 
            liquidity,
            false) >= amountA 
        &&
        test.getAmount0Delta(
            test.getNextSqrtPriceFromInput(sqrtP, liquidity, amountB, true), 
            sqrtP, 
            liquidity,
            true
        ) <= amountB;
}

rule checkAxiomA(uint160 sqrtP, uint128 liquidity, uint256 amountA, uint256 amountB)  {
    /// Limiting cases, otherwise, times-out.
    if(liquidity < (1 << 96)) {
        require liquidity == 1;
        assert axiomA(sqrtP, liquidity, amountA, amountB);
    } else if(liquidity < max_uint128) {
        require liquidity ==  1 << 96;
        assert axiomA(sqrtP, liquidity, amountA, amountB);
    } else {
        require liquidity == max_uint128;
        assert axiomA(sqrtP, liquidity, amountA, amountB);
    }
}

rule checkAxiomB(uint160 sqrtP, uint128 liquidity, uint256 amountA, uint256 amountB)  {
    assert isValidSqrt(sqrtP) =>
        test.getAmount1Delta(
            sqrtP, 
            test.getNextSqrtPriceFromOutput(sqrtP, liquidity, amountA, true), 
            liquidity,
            false
        ) >= amountA 
        &&
        test.getAmount1Delta(
            test.getNextSqrtPriceFromInput(sqrtP, liquidity, amountB, false), 
            sqrtP, 
            liquidity,
            true
        ) <= amountB;
}

rule checkAxiomC(uint160 sqrtP, uint128 liquidity, uint256 amountA, uint256 amountB) {
    /// zeroForOne = true
    assert test.getNextSqrtPriceFromInput(sqrtP, liquidity, amountA, true) <= sqrtP;
    /// zeroForOne = false
    assert test.getNextSqrtPriceFromInput(sqrtP, liquidity, amountA, false) >= sqrtP;
    /// zeroForOne = true
    assert test.getNextSqrtPriceFromOutput(sqrtP, liquidity, amountB, true) <= sqrtP;
    /// zeroForOne = false
    assert test.getNextSqrtPriceFromOutput(sqrtP, liquidity, amountB, false) >= sqrtP;
}

rule checkAxiomD(uint160 sqrtP, uint160 sqrtQ, uint128 liquidity, uint256 amount) {
    bool zeroForOne = sqrtP >= sqrtQ;
    require isValidSqrt(sqrtP);
    require isValidSqrt(sqrtQ);

    uint256 amountBound0 = test.getAmount0Delta(sqrtQ, sqrtP, liquidity, zeroForOne);
    uint256 amountBound1 = test.getAmount1Delta(sqrtQ, sqrtP, liquidity, !zeroForOne);
    uint160 nextSqrtPriceInput = test.getNextSqrtPriceFromInput(sqrtP, liquidity, amount, zeroForOne);
    uint160 nextSqrtPriceOutput = test.getNextSqrtPriceFromOutput(sqrtP, liquidity, amount, zeroForOne);

    if (zeroForOne) {
        assert amount <= amountBound1 => sqrtQ <= nextSqrtPriceOutput && nextSqrtPriceOutput <= sqrtP;
        assert amount < amountBound0 => sqrtQ <= nextSqrtPriceInput && nextSqrtPriceInput <= sqrtP;
    } else {
        assert amount <= amountBound0 => sqrtQ >= nextSqrtPriceOutput && nextSqrtPriceOutput >= sqrtP;
        assert amount < amountBound1 => sqrtQ >= nextSqrtPriceInput && nextSqrtPriceInput >= sqrtP;
    }
}

rule getNextSqrtPriceFromInput_amountDelta_cannot_revert(uint160 sqrtP, uint128 liquidity, uint256 amountIn, bool zeroForOne) {
    require isValidSqrt(sqrtP);
    require amountIn <= max_uint128;

    uint160 sqrtQ = test.getNextSqrtPriceFromInput(sqrtP, liquidity, amountIn, zeroForOne);

    if (zeroForOne) {
        test.getAmount0Delta@withrevert(sqrtQ, sqrtP, liquidity, true);
    } else {
        test.getAmount1Delta@withrevert(sqrtP, sqrtQ, liquidity, true);
    }
    
    assert !lastReverted;
}

rule getNextSqrtPriceFromOutput_amountDelta_cannot_revert(uint160 sqrtP, uint128 liquidity, uint256 amountOut, bool zeroForOne) {
    require isValidSqrt(sqrtP);
    require amountOut <= max_uint128;

    uint160 sqrtQ = test.getNextSqrtPriceFromOutput(sqrtP, liquidity, amountOut, zeroForOne);

    if (zeroForOne) {
        test.getAmount1Delta@withrevert(sqrtQ, sqrtP, liquidity, false);
    } else {
        test.getAmount0Delta@withrevert(sqrtP, sqrtQ, liquidity, false);
    }
    
    assert !lastReverted;
}