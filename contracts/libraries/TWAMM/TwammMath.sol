// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ABDKMathQuad} from 'abdk-libraries-solidity/ABDKMathQuad.sol';
import {TWAMM} from './TWAMM.sol';
import {Tick} from '../Tick.sol';
import {FixedPoint96} from '../FixedPoint96.sol';
import {SafeCast} from '../SafeCast.sol';
import {TickMath} from '../TickMath.sol';
import 'hardhat/console.sol';

/// @title TWAMM Math - Pure functions for TWAMM math calculations
library TwammMath {
    using ABDKMathQuad for *;
    using SafeCast for *;

    // ABDKMathQuad FixedPoint96.Q96.fromUInt()
    bytes16 constant Q96 = 0x405f0000000000000000000000000000;

    struct PriceParamsBytes16 {
        bytes16 sqrtSellRatioX96;
        bytes16 sqrtSellRate;
        bytes16 secondsElapsed;
        bytes16 sqrtPriceX96;
        bytes16 liquidity;
    }

    function getNewSqrtPriceX96(
        uint256 secondsElapsed,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        TWAMM.OrderPoolParamsOnExecute memory orderParams
    ) internal view returns (uint160 newSqrtPriceX96) {
        bytes16 sellRateBytes0 = orderParams.sellRateCurrent0.fromUInt();
        bytes16 sellRateBytes1 = orderParams.sellRateCurrent1.fromUInt();

        bytes16 sqrtSellRatioX96 = sellRateBytes1.div(sellRateBytes0).sqrt().mul(Q96);
        bytes16 sqrtSellRate = sellRateBytes0.mul(sellRateBytes1).sqrt();

        PriceParamsBytes16 memory params = PriceParamsBytes16({
            sqrtSellRatioX96: sqrtSellRatioX96,
            sqrtSellRate: sqrtSellRate,
            secondsElapsed: secondsElapsed.fromUInt(),
            sqrtPriceX96: sqrtPriceX96.fromUInt(),
            liquidity: liquidity.fromUInt()
        });

        bytes16 newSqrtPriceBytesX96 = calculateNewSqrtPriceX96(params);

        bool isOverflow;
        bool isUnderflow;
        // TODO: cleanup with abdk
        //uint256 exponent = (uint128(newSqrtPriceBytesX96) >> 112) & 0x7FFF;
        unchecked {
            uint256 exponent = (uint128(newSqrtPriceBytesX96) >> 112) & 0x7FFF;
            if (exponent < 16383) {
                isUnderflow = true;
            } else {
                isOverflow = exponent > 16638;
            }
        }

        // TODO: Set condition for min.
        newSqrtPriceX96 = isOverflow ? (TickMath.MAX_SQRT_RATIO - 1) : newSqrtPriceBytesX96.toUInt().toUint160();
    }

    function calculateEarningsUpdates(
        uint256 secondsElapsed,
        uint160 sqrtPriceX96,
        uint160 finalSqrtPriceX96,
        uint128 liquidity,
        TWAMM.OrderPoolParamsOnExecute memory orderParams
    ) internal view returns (uint256 earningsFactorPool0, uint256 earningsFactorPool1) {
        bytes16 sellRateBytes0 = orderParams.sellRateCurrent0.fromUInt();
        bytes16 sellRateBytes1 = orderParams.sellRateCurrent1.fromUInt();

        bytes16 sellRatio = sellRateBytes1.div(sellRateBytes0);
        bytes16 sqrtSellRate = sellRateBytes0.mul(sellRateBytes1).sqrt();

        uint256 totalSecondsElapsed = secondsElapsed;
        // TODO check the min.
        if (finalSqrtPriceX96 == (TickMath.MAX_SQRT_RATIO - 1)) {
            // recalculate seconds to final price
            secondsElapsed = calculateTimeBetweenTicks(
                liquidity,
                sqrtPriceX96,
                finalSqrtPriceX96,
                orderParams.sellRateCurrent0,
                orderParams.sellRateCurrent1
            );
        }

        EarningsFactorParams memory earningsFactorParams = EarningsFactorParams({
            secondsElapsedX96: secondsElapsed.fromUInt(),
            sellRatio: sellRatio,
            sqrtSellRate: sqrtSellRate,
            prevSqrtPriceX96: sqrtPriceX96.fromUInt(),
            newSqrtPriceX96: finalSqrtPriceX96.fromUInt(),
            liquidity: liquidity.fromUInt()
        });

        // Trade the amm orders.
        // If liquidity is 0, it trades the twamm orders against eachother for the time duration.
        earningsFactorPool0 = getEarningsFactorPool0(earningsFactorParams).toUInt();
        earningsFactorPool1 = getEarningsFactorPool1(earningsFactorParams).toUInt();

        // If there are still more seconds, trade the twamm orders against eachother for secondsRemaining.
        uint256 secondsRemaining = totalSecondsElapsed - secondsElapsed;
        if (secondsRemaining > 0) {
            earningsFactorPool0 += secondsRemaining.fromUInt().mul(sellRatio).toUInt();
            earningsFactorPool1 += secondsRemaining.fromUInt().mul(reciprocal(sellRatio)).toUInt();
        }
    }

    struct calculateTimeBetweenTicksParams {
        uint256 liquidity;
        uint160 sqrtPriceStartX96;
        uint160 sqrtPriceEndX96;
        uint256 sellRate0;
        uint256 sellRate1;
    }

    /// @notice Used when crossing an initialized tick. Can extract the amount of seconds it took to cross
    ///   the tick, and recalibrate the calculation from there to accommodate liquidity changes
    // todo: this does not work when we push the price to the edge.
    // desmos returning undefined or negative
    function calculateTimeBetweenTicks(
        uint256 liquidity,
        uint160 sqrtPriceStartX96,
        uint160 sqrtPriceEndX96,
        uint256 sellRate0,
        uint256 sellRate1
    ) internal view returns (uint256 secondsBetween) {
        bytes16 sellRate0Bytes = sellRate0.fromUInt();
        bytes16 sellRate1Bytes = sellRate1.fromUInt();
        bytes16 sqrtPriceStartX96Bytes = sqrtPriceStartX96.fromUInt();
        bytes16 sqrtPriceEndX96Bytes = sqrtPriceEndX96.fromUInt();
        bytes16 sqrtSellRatioX96 = sellRate1Bytes.div(sellRate0Bytes).sqrt().mul(Q96);
        bytes16 sqrtSellRate = sellRate0Bytes.mul(sellRate1Bytes).sqrt();

        bytes16 multiple = getTimeBetweenTicksMultiple(sqrtSellRatioX96, sqrtPriceStartX96Bytes, sqrtPriceEndX96Bytes);
        bytes16 numerator = multiple.mul(liquidity.fromUInt());
        bytes16 denominator = uint256(2).fromUInt().mul(sqrtSellRate);
        return numerator.mul(Q96).div(denominator).toUInt();
    }

    // todo: this does not work when we push the price to the edge.
    // desmos returning undefined or negative
    function getTimeBetweenTicksMultiple(
        bytes16 sqrtSellRatioX96,
        bytes16 sqrtPriceStartX96,
        bytes16 sqrtPriceEndX96
    ) private pure returns (bytes16 multiple) {
        bytes16 multiple1 = sqrtSellRatioX96.add(sqrtPriceEndX96).div(sqrtSellRatioX96.sub(sqrtPriceEndX96));
        bytes16 multiple2 = sqrtSellRatioX96.sub(sqrtPriceStartX96).div(sqrtSellRatioX96.add(sqrtPriceStartX96));
        return multiple1.mul(multiple2).ln();
    }

    struct EarningsFactorParams {
        bytes16 secondsElapsedX96;
        bytes16 sellRatio;
        bytes16 sqrtSellRate;
        bytes16 prevSqrtPriceX96;
        bytes16 newSqrtPriceX96;
        bytes16 liquidity;
    }

    function getEarningsFactorPool0(EarningsFactorParams memory params) private pure returns (bytes16 earningsFactor) {
        bytes16 minuend = params.sellRatio.mul(Q96).mul(params.secondsElapsedX96).div(Q96);
        bytes16 subtrahend = params
            .liquidity
            .mul(params.sellRatio.sqrt())
            .mul(params.newSqrtPriceX96.sub(params.prevSqrtPriceX96))
            .div(params.sqrtSellRate);
        return minuend.sub(subtrahend);
    }

    function getEarningsFactorPool1(EarningsFactorParams memory params) private pure returns (bytes16 earningsFactor) {
        bytes16 minuend = params.secondsElapsedX96.div(Q96).div(params.sellRatio);
        bytes16 subtrahend = params
            .liquidity
            .mul(reciprocal(params.sellRatio.sqrt()))
            .mul(reciprocal(params.newSqrtPriceX96).mul(Q96).sub(reciprocal(params.prevSqrtPriceX96).mul(Q96)))
            .div(params.sqrtSellRate);
        return minuend.sub(subtrahend).mul(Q96);
    }

    function calculateNewSqrtPriceX96(PriceParamsBytes16 memory params) private view returns (bytes16 newSqrtPriceX96) {
        bytes16 pow = uint256(2)
            .fromUInt()
            .mul(params.sqrtSellRate)
            .mul(params.secondsElapsed)
            .div(params.liquidity)
            .div(Q96);
        bytes16 c = params.sqrtSellRatioX96.sub(params.sqrtPriceX96).div(
            params.sqrtSellRatioX96.add(params.sqrtPriceX96)
        );
        newSqrtPriceX96 = params.sqrtSellRatioX96.mul(pow.exp().sub(c)).div(pow.exp().add(c));
    }

    function reciprocal(bytes16 n) private pure returns (bytes16) {
        return uint256(1).fromUInt().div(n);
    }
}
