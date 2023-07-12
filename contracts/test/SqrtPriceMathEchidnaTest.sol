// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {FullMath} from "../libraries/FullMath.sol";
import {SqrtPriceMath} from "../libraries/SqrtPriceMath.sol";
import {FixedPoint96, UQ64x96} from "../libraries/FixedPoint96.sol";

contract SqrtPriceMathEchidnaTest {
    function mulDivRoundingUpInvariants(uint256 x, uint256 y, uint256 z) external pure {
        unchecked {
            require(z > 0);
            uint256 notRoundedUp = FullMath.mulDiv(x, y, z);
            uint256 roundedUp = FullMath.mulDivRoundingUp(x, y, z);
            assert(roundedUp >= notRoundedUp);
            assert(roundedUp - notRoundedUp < 2);
            if (roundedUp - notRoundedUp == 1) {
                assert(mulmod(x, y, z) > 0);
            } else {
                assert(mulmod(x, y, z) == 0);
            }
        }
    }

    function getNextSqrtPriceFromInputInvariants(uint160 sqrtPX96, uint128 liquidity, uint256 amountIn, bool zeroForOne)
        external
        pure
    {
        UQ64x96 sqrtP = UQ64x96.wrap(sqrtPX96);
        UQ64x96 sqrtQ = SqrtPriceMath.getNextSqrtPriceFromInput(sqrtP, liquidity, amountIn, zeroForOne);

        if (zeroForOne) {
            assert(sqrtQ <= sqrtP);
            assert(amountIn >= SqrtPriceMath.getAmount0Delta(sqrtQ, sqrtP, liquidity, true));
        } else {
            assert(sqrtQ >= sqrtP);
            assert(amountIn >= SqrtPriceMath.getAmount1Delta(sqrtP, sqrtQ, liquidity, true));
        }
    }

    function getNextSqrtPriceFromOutputInvariants(
        uint160 sqrtPX96,
        uint128 liquidity,
        uint256 amountOut,
        bool zeroForOne
    ) external pure {
        UQ64x96 sqrtP = UQ64x96.wrap(sqrtPX96);
        UQ64x96 sqrtQ = SqrtPriceMath.getNextSqrtPriceFromOutput(sqrtP, liquidity, amountOut, zeroForOne);

        if (zeroForOne) {
            assert(sqrtQ <= sqrtP);
            assert(amountOut <= SqrtPriceMath.getAmount1Delta(sqrtQ, sqrtP, liquidity, false));
        } else {
            assert(sqrtQ > UQ64x96.wrap(0)); // this has to be true, otherwise we need another require
            assert(sqrtQ >= sqrtP);
            assert(amountOut <= SqrtPriceMath.getAmount0Delta(sqrtP, sqrtQ, liquidity, false));
        }
    }

    function getNextSqrtPriceFromAmount0RoundingUpInvariants(
        uint160 sqrtPX96,
        uint128 liquidity,
        uint256 amount,
        bool add
    ) external pure {
        require(sqrtPX96 > 0);
        require(liquidity > 0);
        UQ64x96 sqrtP = UQ64x96.wrap(sqrtPX96);
        UQ64x96 sqrtQ = SqrtPriceMath.getNextSqrtPriceFromAmount0RoundingUp(sqrtP, liquidity, amount, add);

        if (add) {
            assert(sqrtQ <= sqrtP);
        } else {
            assert(sqrtQ >= sqrtP);
        }

        if (amount == 0) {
            assert(sqrtP == sqrtQ);
        }
    }

    function getNextSqrtPriceFromAmount1RoundingDownInvariants(
        uint160 sqrtPX96,
        uint128 liquidity,
        uint256 amount,
        bool add
    ) external pure {
        require(sqrtPX96 > 0);
        require(liquidity > 0);
        UQ64x96 sqrtP = UQ64x96.wrap(sqrtPX96);
        UQ64x96 sqrtQ = SqrtPriceMath.getNextSqrtPriceFromAmount1RoundingDown(sqrtP, liquidity, amount, add);

        if (add) {
            assert(sqrtQ >= sqrtP);
        } else {
            assert(sqrtQ <= sqrtP);
        }

        if (amount == 0) {
            assert(sqrtP == sqrtQ);
        }
    }

    function getAmount0DeltaInvariants(uint160 sqrtPX96, uint160 sqrtQX96, uint128 liquidity) external pure {
        require(sqrtPX96 > 0 && sqrtQX96 > 0);
        UQ64x96 sqrtQ = UQ64x96.wrap(sqrtQX96);
        UQ64x96 sqrtP = UQ64x96.wrap(sqrtPX96);

        uint256 amount0Down = SqrtPriceMath.getAmount0Delta(sqrtQ, sqrtP, liquidity, false);
        assert(amount0Down == SqrtPriceMath.getAmount0Delta(sqrtP, sqrtQ, liquidity, false));

        uint256 amount0Up = SqrtPriceMath.getAmount0Delta(sqrtQ, sqrtP, liquidity, true);
        assert(amount0Up == SqrtPriceMath.getAmount0Delta(sqrtP, sqrtQ, liquidity, true));

        assert(amount0Down <= amount0Up);
        // diff is 0 or 1
        assert(amount0Up - amount0Down < 2);
    }

    // ensure that chained division is always equal to the full-precision case for
    // liquidity * (sqrt(P) - sqrt(Q)) / (sqrt(P) * sqrt(Q))
    function getAmount0DeltaEquivalency(uint160 sqrtPX96, uint160 sqrtQX96, uint128 liquidity, bool roundUp)
        external
        pure
    {
        require(sqrtPX96 >= sqrtQX96);
        require(sqrtPX96 > 0 && sqrtQX96 > 0);
        require((sqrtPX96 * sqrtQX96) / sqrtPX96 == sqrtQX96);

        UQ64x96 sqrtQ = UQ64x96.wrap(sqrtQX96);
        UQ64x96 sqrtP = UQ64x96.wrap(sqrtPX96);

        uint256 numerator1 = uint256(liquidity) << FixedPoint96.RESOLUTION;
        uint256 numerator2 = UQ64x96.unwrap(sqrtP - sqrtQ);
        uint256 denominator = UQ64x96.unwrap(sqrtP * sqrtQ);

        uint256 safeResult = roundUp
            ? FullMath.mulDivRoundingUp(numerator1, numerator2, denominator)
            : FullMath.mulDiv(numerator1, numerator2, denominator);
        uint256 fullResult = SqrtPriceMath.getAmount0Delta(sqrtQ, sqrtP, liquidity, roundUp);

        assert(safeResult == fullResult);
    }

    function getAmount1DeltaInvariants(uint160 sqrtPX96, uint160 sqrtQX96, uint128 liquidity) external pure {
        require(sqrtPX96 > 0 && sqrtQX96 > 0);
        UQ64x96 sqrtQ = UQ64x96.wrap(sqrtQX96);
        UQ64x96 sqrtP = UQ64x96.wrap(sqrtPX96);

        uint256 amount1Down = SqrtPriceMath.getAmount1Delta(sqrtP, sqrtQ, liquidity, false);
        assert(amount1Down == SqrtPriceMath.getAmount1Delta(sqrtQ, sqrtP, liquidity, false));

        uint256 amount1Up = SqrtPriceMath.getAmount1Delta(sqrtP, sqrtQ, liquidity, true);
        assert(amount1Up == SqrtPriceMath.getAmount1Delta(sqrtQ, sqrtP, liquidity, true));

        assert(amount1Down <= amount1Up);
        // diff is 0 or 1
        assert(amount1Up - amount1Down < 2);
    }

    function getAmount0DeltaSignedInvariants(uint160 sqrtPX96, uint160 sqrtQX96, int128 liquidity) external pure {
        require(sqrtPX96 > 0 && sqrtQX96 > 0);

        UQ64x96 sqrtQ = UQ64x96.wrap(sqrtQX96);
        UQ64x96 sqrtP = UQ64x96.wrap(sqrtPX96);

        int256 amount0 = SqrtPriceMath.getAmount0Delta(sqrtQ, sqrtP, liquidity);
        if (liquidity < 0) assert(amount0 <= 0);
        if (liquidity > 0) {
            if (sqrtP == sqrtQ) assert(amount0 == 0);
            else assert(amount0 > 0);
        }
        if (liquidity == 0) assert(amount0 == 0);
    }

    function getAmount1DeltaSignedInvariants(uint160 sqrtPX96, uint160 sqrtQX96, int128 liquidity) external pure {
        require(sqrtPX96 > 0 && sqrtQX96 > 0);

        UQ64x96 sqrtQ = UQ64x96.wrap(sqrtQX96);
        UQ64x96 sqrtP = UQ64x96.wrap(sqrtPX96);

        int256 amount1 = SqrtPriceMath.getAmount1Delta(sqrtP, sqrtQ, liquidity);
        if (liquidity < 0) assert(amount1 <= 0);
        if (liquidity > 0) {
            if (sqrtP == sqrtQ) assert(amount1 == 0);
            else assert(amount1 > 0);
        }
        if (liquidity == 0) assert(amount1 == 0);
    }

    function getOutOfRangeMintInvariants(uint160 sqrtAX96, uint160 sqrtBX96, int128 liquidity) external pure {
        require(sqrtAX96 > 0 && sqrtAX96 > 0);
        require(liquidity > 0);

        UQ64x96 sqrtA = UQ64x96.wrap(sqrtAX96);
        UQ64x96 sqrtB = UQ64x96.wrap(sqrtBX96);

        int256 amount0 = SqrtPriceMath.getAmount0Delta(sqrtA, sqrtB, liquidity);
        int256 amount1 = SqrtPriceMath.getAmount1Delta(sqrtA, sqrtB, liquidity);

        if (sqrtA == sqrtB) {
            assert(amount0 == 0);
            assert(amount1 == 0);
        } else {
            assert(amount0 > 0);
            assert(amount1 > 0);
        }
    }

    function getInRangeMintInvariants(
        uint160 sqrtLowerX96,
        uint160 sqrtCurrentX96,
        uint160 sqrtUpperX96,
        int128 liquidity
    ) external pure {
        require(sqrtLowerX96 > 0);
        require(sqrtLowerX96 < sqrtUpperX96);
        require(sqrtLowerX96 <= sqrtCurrentX96 && sqrtCurrentX96 <= sqrtUpperX96);
        require(liquidity > 0);

        UQ64x96 sqrtLower = UQ64x96.wrap(sqrtLowerX96);
        UQ64x96 sqrtCurrent = UQ64x96.wrap(sqrtCurrentX96);
        UQ64x96 sqrtUpper = UQ64x96.wrap(sqrtUpperX96);

        int256 amount0 = SqrtPriceMath.getAmount0Delta(sqrtCurrent, sqrtUpper, liquidity);
        int256 amount1 = SqrtPriceMath.getAmount1Delta(sqrtLower, sqrtCurrent, liquidity);

        assert(amount0 > 0 || amount1 > 0);
    }
}
