// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {SqrtPriceMath} from "../libraries/SqrtPriceMath.sol";
import {UQ64x96} from "../libraries/FixedPoint96.sol";

contract SqrtPriceMathTest {
    function getNextSqrtPriceFromInput(uint160 sqrtPX96, uint128 liquidity, uint256 amountIn, bool zeroForOne)
        external
        pure
        returns (uint160 sqrtQ)
    {
        UQ64x96 sqrtP = UQ64x96.wrap(sqrtPX96);
        return UQ64x96.unwrap(SqrtPriceMath.getNextSqrtPriceFromInput(sqrtP, liquidity, amountIn, zeroForOne));
    }

    function getGasCostOfGetNextSqrtPriceFromInput(
        uint160 sqrtPX96,
        uint128 liquidity,
        uint256 amountIn,
        bool zeroForOne
    ) external view returns (uint256) {
        UQ64x96 sqrtP = UQ64x96.wrap(sqrtPX96);
        uint256 gasBefore = gasleft();
        SqrtPriceMath.getNextSqrtPriceFromInput(sqrtP, liquidity, amountIn, zeroForOne);
        return gasBefore - gasleft();
    }

    function getNextSqrtPriceFromOutput(uint160 sqrtPX96, uint128 liquidity, uint256 amountOut, bool zeroForOne)
        external
        pure
        returns (uint160 sqrtQ)
    {
        UQ64x96 sqrtP = UQ64x96.wrap(sqrtPX96);
        return UQ64x96.unwrap(SqrtPriceMath.getNextSqrtPriceFromOutput(sqrtP, liquidity, amountOut, zeroForOne));
    }

    function getGasCostOfGetNextSqrtPriceFromOutput(
        uint160 sqrtPX96,
        uint128 liquidity,
        uint256 amountOut,
        bool zeroForOne
    ) external view returns (uint256) {
        UQ64x96 sqrtP = UQ64x96.wrap(sqrtPX96);
        uint256 gasBefore = gasleft();
        SqrtPriceMath.getNextSqrtPriceFromOutput(sqrtP, liquidity, amountOut, zeroForOne);
        return gasBefore - gasleft();
    }

    function getAmount0Delta(uint160 sqrtLowerX96, uint160 sqrtUpperX96, uint128 liquidity, bool roundUp)
        external
        pure
        returns (uint256 amount0)
    {
        UQ64x96 sqrtLower = UQ64x96.wrap(sqrtLowerX96);
        UQ64x96 sqrtUpper = UQ64x96.wrap(sqrtUpperX96);
        return SqrtPriceMath.getAmount0Delta(sqrtLower, sqrtUpper, liquidity, roundUp);
    }

    function getAmount1Delta(uint160 sqrtLowerX96, uint160 sqrtUpperX96, uint128 liquidity, bool roundUp)
        external
        pure
        returns (uint256 amount1)
    {
        UQ64x96 sqrtLower = UQ64x96.wrap(sqrtLowerX96);
        UQ64x96 sqrtUpper = UQ64x96.wrap(sqrtUpperX96);
        return SqrtPriceMath.getAmount1Delta(sqrtLower, sqrtUpper, liquidity, roundUp);
    }

    function getGasCostOfGetAmount0Delta(uint160 sqrtLowerX96, uint160 sqrtUpperX96, uint128 liquidity, bool roundUp)
        external
        view
        returns (uint256)
    {
        UQ64x96 sqrtLower = UQ64x96.wrap(sqrtLowerX96);
        UQ64x96 sqrtUpper = UQ64x96.wrap(sqrtUpperX96);
        uint256 gasBefore = gasleft();
        SqrtPriceMath.getAmount0Delta(sqrtLower, sqrtUpper, liquidity, roundUp);
        return gasBefore - gasleft();
    }

    function getGasCostOfGetAmount1Delta(uint160 sqrtLowerX96, uint160 sqrtUpperX96, uint128 liquidity, bool roundUp)
        external
        view
        returns (uint256)
    {
        UQ64x96 sqrtLower = UQ64x96.wrap(sqrtLowerX96);
        UQ64x96 sqrtUpper = UQ64x96.wrap(sqrtUpperX96);
        uint256 gasBefore = gasleft();
        SqrtPriceMath.getAmount1Delta(sqrtLower, sqrtUpper, liquidity, roundUp);
        return gasBefore - gasleft();
    }
}
