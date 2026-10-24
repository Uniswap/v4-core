// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { SqrtPriceMath } from "src/libraries/SqrtPriceMath.sol";

contract SqrtPriceMathTest {

    function getNextSqrtPriceFromInput(uint160 sqrtPX96, uint128 liquidity, uint256 amountIn, bool zeroForOne)
        external pure returns (uint160 sqrtQX96) 
    {
        return SqrtPriceMath.getNextSqrtPriceFromInput(sqrtPX96, liquidity, amountIn, zeroForOne);
    }

    function getNextSqrtPriceFromOutput(uint160 sqrtPX96, uint128 liquidity, uint256 amountOut, bool zeroForOne)
        external pure returns (uint160 sqrtQX96)
    {
        return SqrtPriceMath.getNextSqrtPriceFromOutput(sqrtPX96, liquidity, amountOut, zeroForOne);
    }

    function getAmount0Delta(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint128 liquidity, bool roundUp)
        external pure returns (uint256 amount0)
    {
        return SqrtPriceMath.getAmount0Delta(sqrtPriceAX96, sqrtPriceBX96, liquidity, roundUp);
    }

    function getAmount1Delta(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint128 liquidity, bool roundUp)
        external pure returns (uint256 amount1)
    {
        return SqrtPriceMath.getAmount1Delta(sqrtPriceAX96, sqrtPriceBX96, liquidity, roundUp);
    }
}
