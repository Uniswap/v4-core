/// All of these methods are pure so a deterministic ghost function summary is a valid over-approximation by definition.

// A minimal deterministic summary for the `SqrtPriceMath` library functions.
// The function values aren't restricted in any way but are guaranteed to behave deterministically.
// Use this summarization for rules that do not concern liquidity <-> token amounts conversions, and only concern general assertions.
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

persistent ghost nextSqrtPriceFromInput(uint160,uint128,uint256,bool) returns uint160;
persistent ghost nextSqrtPriceFromOutput(uint160,uint128,uint256,bool) returns uint160;
persistent ghost amount0Delta(uint160,uint160,uint128,bool) returns uint256;
persistent ghost amount1Delta(uint160,uint160,uint128,bool) returns uint256;