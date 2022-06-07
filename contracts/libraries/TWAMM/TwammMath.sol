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
        bytes16 sqrtSellRatio;
        bytes16 sqrtSellRate;
        bytes16 secondsElapsed;
        bytes16 sqrtPrice;
        bytes16 liquidity;
    }

    struct ExecutionUpdateParams {
        uint256 secondsElapsedX96;
        uint160 sqrtPriceX96;
        uint128 liquidity;
        uint256 sellRateCurrent0;
        uint256 sellRateCurrent1;
    }

    // change to pure
    function getNewSqrtPriceX96(ExecutionUpdateParams memory params) internal view returns (uint160 newSqrtPriceX96) {
        bool zeroForOne = params.sellRateCurrent0 > params.sellRateCurrent1;

        bytes16 sellRateBytes0 = params.sellRateCurrent0.fromUInt();
        bytes16 sellRateBytes1 = params.sellRateCurrent1.fromUInt();
        bytes16 sqrtSellRate = sellRateBytes0.mul(sellRateBytes1).sqrt();
        bytes16 sqrtSellRatioX96 = sellRateBytes1.div(sellRateBytes0).sqrt().mul(Q96);

        PriceParamsBytes16 memory priceParams = PriceParamsBytes16({
            sqrtSellRatio: sqrtSellRatioX96.div(Q96),
            sqrtSellRate: sqrtSellRate,
            secondsElapsed: params.secondsElapsedX96.fromUInt().div(Q96),
            sqrtPrice: params.sqrtPriceX96.fromUInt().div(Q96),
            liquidity: params.liquidity.fromUInt()
        });

        bytes16 newSqrtPriceBytesX96 = calculateNewSqrtPrice(priceParams).mul(Q96);
        bool isOverflow = newSqrtPriceBytesX96.isInfinity() || newSqrtPriceBytesX96.isNaN();

        if (isOverflow) {
            // If overflow, the final price is set to the sqrtSellRatio.
            // Ensure that the sqrtSellRatio is not greater than the max or below the min.
            newSqrtPriceX96 = getSqrtPriceWithinBounds(zeroForOne, sqrtSellRatioX96).toUInt().toUint160();
        } else {
            // Ensure the calculated price is not greater than the max or below the min.
            newSqrtPriceX96 = getSqrtPriceWithinBounds(zeroForOne, newSqrtPriceBytesX96).toUInt().toUint160();
        }
    }

    function getSqrtPriceWithinBounds(bool zeroForOne, bytes16 desiredPriceX96)
        internal
        view
        returns (bytes16 newSqrtPriceX96)
    {
        bytes16 maxPriceBytesX96 = TickMath.MAX_SQRT_RATIO.fromUInt();
        bytes16 minPriceBytesX96 = TickMath.MIN_SQRT_RATIO.fromUInt();

        if (zeroForOne) {
            int8 isLessThanMinimum = minPriceBytesX96.cmp(desiredPriceX96);
            newSqrtPriceX96 = isLessThanMinimum == 1 ? minPriceBytesX96 : desiredPriceX96;
        } else {
            int8 isGreaterThanMaximum = desiredPriceX96.cmp(maxPriceBytesX96);
            newSqrtPriceX96 = isGreaterThanMaximum == 1 ? maxPriceBytesX96 : desiredPriceX96;
        }
    }

    function calculateEarningsUpdates(ExecutionUpdateParams memory params, uint160 finalSqrtPriceX96)
        internal
        pure
        returns (uint256 earningsFactorPool0, uint256 earningsFactorPool1)
    {
        bytes16 sellRateBytes0 = params.sellRateCurrent0.fromUInt();
        bytes16 sellRateBytes1 = params.sellRateCurrent1.fromUInt();

        bytes16 sellRatio = sellRateBytes1.div(sellRateBytes0);
        bytes16 sqrtSellRate = sellRateBytes0.mul(sellRateBytes1).sqrt();

        EarningsFactorParams memory earningsFactorParams = EarningsFactorParams({
            secondsElapsed: params.secondsElapsedX96.fromUInt().div(Q96),
            sellRatio: sellRatio,
            sqrtSellRate: sqrtSellRate,
            prevSqrtPrice: params.sqrtPriceX96.fromUInt().div(Q96),
            newSqrtPrice: finalSqrtPriceX96.fromUInt().div(Q96),
            liquidity: params.liquidity.fromUInt()
        });

        // Trade the amm orders.
        // If liquidity is 0, it trades the twamm orders against eachother for the time duration.
        earningsFactorPool0 = getEarningsFactorPool0(earningsFactorParams).mul(Q96).toUInt();
        earningsFactorPool1 = getEarningsFactorPool1(earningsFactorParams).mul(Q96).toUInt();
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
    // change to pure
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

    // change to pure
    function getTimeBetweenTicksMultiple(
        bytes16 sqrtSellRatioX96,
        bytes16 sqrtPriceStartX96,
        bytes16 sqrtPriceEndX96
    ) private view returns (bytes16 multiple) {
        bytes16 multiple1 = sqrtSellRatioX96.add(sqrtPriceEndX96).div(sqrtSellRatioX96.sub(sqrtPriceEndX96));
        bytes16 multiple2 = sqrtSellRatioX96.sub(sqrtPriceStartX96).div(sqrtSellRatioX96.add(sqrtPriceStartX96));
        return multiple1.mul(multiple2).ln();
    }

    struct EarningsFactorParams {
        bytes16 secondsElapsed;
        bytes16 sellRatio;
        bytes16 sqrtSellRate;
        bytes16 prevSqrtPrice;
        bytes16 newSqrtPrice;
        bytes16 liquidity;
    }

    function getEarningsFactorPool0(EarningsFactorParams memory params) private pure returns (bytes16 earningsFactor) {
        bytes16 minuend = params.sellRatio.mul(params.secondsElapsed);
        bytes16 subtrahend = params
            .liquidity
            .mul(params.sellRatio.sqrt())
            .mul(params.newSqrtPrice.sub(params.prevSqrtPrice))
            .div(params.sqrtSellRate);
        return minuend.sub(subtrahend);
    }

    function getEarningsFactorPool1(EarningsFactorParams memory params) private pure returns (bytes16 earningsFactor) {
        bytes16 minuend = params.secondsElapsed.div(params.sellRatio);
        bytes16 subtrahend = params
            .liquidity
            .mul(reciprocal(params.sellRatio.sqrt()))
            .mul(reciprocal(params.newSqrtPrice).sub(reciprocal(params.prevSqrtPrice)))
            .div(params.sqrtSellRate);
        return minuend.sub(subtrahend);
    }

    function calculateNewSqrtPrice(PriceParamsBytes16 memory params) private pure returns (bytes16 newSqrtPrice) {
        bytes16 pow = uint256(2).fromUInt().mul(params.sqrtSellRate).mul(params.secondsElapsed).div(params.liquidity);
        bytes16 c = params.sqrtSellRatio.sub(params.sqrtPrice).div(params.sqrtSellRatio.add(params.sqrtPrice));
        newSqrtPrice = params.sqrtSellRatio.mul(pow.exp().sub(c)).div(pow.exp().add(c));
    }

    function reciprocal(bytes16 n) private pure returns (bytes16) {
        return uint256(1).fromUInt().div(n);
    }
}
