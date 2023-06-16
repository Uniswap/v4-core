// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {SqrtPriceMath} from "../libraries/SqrtPriceMath.sol";

contract SqrtPriceMathTest {
    function getNextSqrtPriceFromAmount0RoundingUp(uint160 sqrtPX96, uint128 liquidity, uint256 amount, bool add)
        external
        pure
        returns (uint160)
    {
        return SqrtPriceMath.getNextSqrtPriceFromAmount0RoundingUp(sqrtPX96, liquidity, amount, add);
    }

    function getNextSqrtPriceFromAmount1RoundingDown(uint160 sqrtPX96, uint128 liquidity, uint256 amount, bool add)
        external
        pure
        returns (uint160)
    {
        return SqrtPriceMath.getNextSqrtPriceFromAmount1RoundingDown(sqrtPX96, liquidity, amount, add);
    }

    function getNextSqrtPriceFromInput(uint160 sqrtP, uint128 liquidity, uint256 amountIn, bool zeroForOne)
        external
        pure
        returns (uint160 sqrtQ)
    {
        return SqrtPriceMath.getNextSqrtPriceFromInput(sqrtP, liquidity, amountIn, zeroForOne);
    }

    function getGasCostOfGetNextSqrtPriceFromInput(uint160 sqrtP, uint128 liquidity, uint256 amountIn, bool zeroForOne)
        external
        view
        returns (uint256)
    {
        uint256 gasBefore = gasleft();
        SqrtPriceMath.getNextSqrtPriceFromInput(sqrtP, liquidity, amountIn, zeroForOne);
        return gasBefore - gasleft();
    }

    function getNextSqrtPriceFromOutput(uint160 sqrtP, uint128 liquidity, uint256 amountOut, bool zeroForOne)
        external
        pure
        returns (uint160 sqrtQ)
    {
        return SqrtPriceMath.getNextSqrtPriceFromOutput(sqrtP, liquidity, amountOut, zeroForOne);
    }

    function getGasCostOfGetNextSqrtPriceFromOutput(
        uint160 sqrtP,
        uint128 liquidity,
        uint256 amountOut,
        bool zeroForOne
    ) external view returns (uint256) {
        uint256 gasBefore = gasleft();
        SqrtPriceMath.getNextSqrtPriceFromOutput(sqrtP, liquidity, amountOut, zeroForOne);
        return gasBefore - gasleft();
    }

    function getAmount0Delta(uint160 sqrtLower, uint160 sqrtUpper, uint128 liquidity, bool roundUp)
        external
        pure
        returns (uint256 amount0)
    {
        return SqrtPriceMath.getAmount0Delta(sqrtLower, sqrtUpper, liquidity, roundUp);
    }

    function getAmount1Delta(uint160 sqrtLower, uint160 sqrtUpper, uint128 liquidity, bool roundUp)
        external
        pure
        returns (uint256 amount1)
    {
        return SqrtPriceMath.getAmount1Delta(sqrtLower, sqrtUpper, liquidity, roundUp);
    }

    function getGasCostOfGetAmount0Delta(uint160 sqrtLower, uint160 sqrtUpper, uint128 liquidity, bool roundUp)
        external
        view
        returns (uint256)
    {
        uint256 gasBefore = gasleft();
        SqrtPriceMath.getAmount0Delta(sqrtLower, sqrtUpper, liquidity, roundUp);
        return gasBefore - gasleft();
    }

    function getGasCostOfGetAmount1Delta(uint160 sqrtLower, uint160 sqrtUpper, uint128 liquidity, bool roundUp)
        external
        view
        returns (uint256)
    {
        uint256 gasBefore = gasleft();
        SqrtPriceMath.getAmount1Delta(sqrtLower, sqrtUpper, liquidity, roundUp);
        return gasBefore - gasleft();
    }

    function getAmount0DeltaSigned(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, int128 liquidity)
        external
        pure
        returns (int256)
    {
        return SqrtPriceMath.getAmount0Delta(sqrtRatioAX96, sqrtRatioBX96, liquidity);
    }

    function getAmount1DeltaSigned(uint160 sqrtRatioAX96, uint160 sqrtRatioBX96, int128 liquidity)
        external
        pure
        returns (int256)
    {
        return SqrtPriceMath.getAmount1Delta(sqrtRatioAX96, sqrtRatioBX96, liquidity);
    }
}
