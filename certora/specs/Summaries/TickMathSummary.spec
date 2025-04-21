import "../Common/TickMathDefinitions.spec";

/// All of these methods are pure so a deterministic ghost function summary is a valid over-approximation by definition.

/// Change sqrtPrice to sqrtPrice.
methods {
    function TickMath.getSqrtPriceAtTick(int24 tick) internal returns (uint160) => getSqrtPriceAtTickCVL(tick);
    function TickMath.getTickAtSqrtPrice(uint160 sqrtPriceX96) internal returns (int24) => getTickAtSqrtPriceCVL(sqrtPriceX96);
}

definition tickAtSqrtPriceRoundDown(int24 tick, uint160 sqrtPrice) returns bool =
    (isValidSqrt(sqrtPrice) && isValidTick(tick)) => sqrtPriceAtTick(tick) > sqrtPrice => tick > tickAtSqrtPrice(sqrtPrice);

function getSqrtPriceAtTickCVL(int24 tick) returns uint160 {
    require isValidTick(tick);
    return sqrtPriceAtTick(tick);
}

function getTickAtSqrtPriceCVL(uint160 sqrtPriceX96) returns int24 {
    require isValidSqrtStrong(sqrtPriceX96);
    return tickAtSqrtPrice(sqrtPriceX96);
}

persistent ghost sqrtPriceAtTick(int24) returns uint160 {
    axiom forall int24 tick. isValidTick(tick) => isValidSqrt(sqrtPriceAtTick(tick));
    axiom sqrtPriceAtTick(MAX_TICK()) == MAX_SQRT_PRICE();
    axiom sqrtPriceAtTick(MIN_TICK()) == MIN_SQRT_PRICE();
    axiom sqrtPriceAtTick(0) == ZERO_TICK_SQRT_PRICE();

    /// Strict monotonicity (verified with a computation loop for all valid inputs):
    axiom forall int24 tick1. forall int24 tick2.
        (isValidTick(tick1) && isValidTick(tick2) && tick1 < tick2) =>
        sqrtPriceAtTick(tick1) < sqrtPriceAtTick(tick2);

    /// Inverse tick -> price -> tick (verified with a computation loop for all valid inputs):
    axiom forall int24 tick.
        isValidTick(tick) => tickAtSqrtPrice(sqrtPriceAtTick(tick)) == tick;
}

persistent ghost tickAtSqrtPrice(uint160) returns int24 {
    axiom forall uint160 sqrtPrice. isValidSqrt(sqrtPrice) => isValidTick(tickAtSqrtPrice(sqrtPrice));
    axiom tickAtSqrtPrice(MIN_SQRT_PRICE()) == MIN_TICK();
    axiom tickAtSqrtPrice(MAX_SQRT_PRICE()) == MAX_TICK();
    axiom tickAtSqrtPrice(Q96_160()) == ONE_RATIO_TICK();
    
    /// Monotonicity:
    axiom forall uint160 price1. forall uint160 price2.
        (isValidSqrt(price1) && isValidSqrt(price2) && price1 < price2) =>
        tickAtSqrtPrice(price1) <= tickAtSqrtPrice(price2);

    /// Rounding down of tickAtSqrtPrice:
    /*
        tickAtSqrtPrice(sqrtPriceAtTick(tick) - 1) == tick - 1 (verified with a computation loop for all valid inputs)
        Therefore:
        forall sqrtPrice <= sqrtPriceAtTick(tick) - 1 < sqrtPriceAtTick(tick) 
            tickAtSqrtPrice(sqrtPrice) < tickAtSqrtPrice(sqrtPriceAtTick(tick)) == tick (proven) 
            tickAtSqrtPrice(sqrtPrice) < tick
        hence:
            sqrtPrice < sqrtPriceAtTick(tick) => tickAtSqrtPrice(sqrtPrice) < tick
    */
    axiom forall uint160 sqrtP. forall int24 tick. tickAtSqrtPriceRoundDown(tick, sqrtP);
}

