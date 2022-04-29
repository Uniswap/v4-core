// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ABDKMathQuad} from 'abdk-libraries-solidity/ABDKMathQuad.sol';
import {TWAMM} from './TWAMM.sol';
import {Tick} from '../Tick.sol';
import {FixedPoint96} from '../FixedPoint96.sol';
import {SafeCast} from '../SafeCast.sol';
import 'hardhat/console.sol';

/// @title TWAMM Math - Pure functions for TWAMM math calculations
library TwammMath {
    using ABDKMathQuad for *;
    using SafeCast for *;

    // ABDKMathQuad FixedPoint96.Q96.fromUInt()
    bytes16 constant Q96 = 0x405f0000000000000000000000000000;

    struct ParamsBytes16 {
        bytes16 sqrtPriceX96;
        bytes16 liquidity;
        bytes16 sellRateCurrent0;
        bytes16 sellRateCurrent1;
        bytes16 secondsElapsedX96;
    }

    struct ExecutionUpdateParams {
        uint256 secondsElapsedX96;
        uint160 sqrtPriceX96;
        uint128 liquidity;
        uint256 sellRateCurrent0;
        uint256 sellRateCurrent1;
    }

    /// @notice Calculation used incrementally (b/w expiration intervals or initialized ticks)
    ///    to calculate earnings rewards and the amm price change resulting from executing TWAMM orders
    function calculateExecutionUpdates(ExecutionUpdateParams memory params)
        internal
        view
        returns (
            uint160 sqrtPriceX96,
            uint256 earningsPool0,
            uint256 earningsPool1
        )
    {
        // https://www.desmos.com/calculator/yr3qvkafvy
        // https://www.desmos.com/calculator/rjcdwnaoja -- tracks some intermediate calcs

        ParamsBytes16 memory bytesParams = ParamsBytes16({
            sqrtPriceX96: params.sqrtPriceX96.fromUInt(),
            liquidity: params.liquidity.fromUInt(),
            sellRateCurrent0: params.sellRateCurrent0.fromUInt(),
            sellRateCurrent1: params.sellRateCurrent1.fromUInt(),
            secondsElapsedX96: params.secondsElapsedX96.fromUInt()
        });

        bytes16 sellRatio = bytesParams.sellRateCurrent1.div(bytesParams.sellRateCurrent0);

        bytes16 sqrtSellRatioX96 = sellRatio.sqrt().mul(Q96);

        bytes16 sqrtSellRate = bytesParams.sellRateCurrent0.mul(bytesParams.sellRateCurrent1).sqrt();

        bytes16 newSqrtPriceX96 = calculateNewSqrtPriceX96(
            sqrtSellRatioX96,
            sqrtSellRate,
            bytesParams.secondsElapsedX96,
            bytesParams
        );

        EarningsFactorParams memory earningsFactorParams = EarningsFactorParams({
            secondsElapsedX96: bytesParams.secondsElapsedX96,
            sellRatio: sellRatio,
            sqrtSellRate: sqrtSellRate,
            prevSqrtPriceX96: bytesParams.sqrtPriceX96,
            newSqrtPriceX96: newSqrtPriceX96,
            liquidity: bytesParams.liquidity
        });

        sqrtPriceX96 = newSqrtPriceX96.toUInt().toUint160();
        earningsPool0 = getEarningsAmountPool0(earningsFactorParams).toUInt();
        earningsPool1 = getEarningsAmountPool1(earningsFactorParams).toUInt();
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

    function getEarningsAmountPool0(EarningsFactorParams memory params) private pure returns (bytes16 earningsFactor) {
        bytes16 minuend = params.sellRatio.mul(Q96).mul(params.secondsElapsedX96).div(Q96);
        bytes16 subtrahend = params
            .liquidity
            .mul(params.sellRatio.sqrt())
            .mul(params.newSqrtPriceX96.sub(params.prevSqrtPriceX96))
            .div(params.sqrtSellRate);
        return minuend.sub(subtrahend);
    }

    function getEarningsAmountPool1(EarningsFactorParams memory params) private pure returns (bytes16 earningsFactor) {
        bytes16 minuend = params.secondsElapsedX96.div(Q96).div(params.sellRatio);
        bytes16 subtrahend = params
            .liquidity
            .mul(reciprocal(params.sellRatio.sqrt()))
            .mul(reciprocal(params.newSqrtPriceX96).mul(Q96).sub(reciprocal(params.prevSqrtPriceX96).mul(Q96)))
            .div(params.sqrtSellRate);
        return minuend.sub(subtrahend).mul(Q96);
    }

    function calculateNewSqrtPriceX96(
        bytes16 sqrtSellRatioX96,
        bytes16 sqrtSellRate,
        bytes16 secondsElapsedX96,
        ParamsBytes16 memory params
    ) private view returns (bytes16 newSqrtPriceX96) {
        bytes16 pow = uint256(2).fromUInt().mul(sqrtSellRate).mul(secondsElapsedX96).div(params.liquidity).div(Q96);
        bytes16 c = sqrtSellRatioX96.sub(params.sqrtPriceX96).div(sqrtSellRatioX96.add(params.sqrtPriceX96));
        newSqrtPriceX96 = sqrtSellRatioX96.mul(pow.exp().sub(c)).div(pow.exp().add(c));
    }

    function reciprocal(bytes16 n) private pure returns (bytes16) {
        return uint256(1).fromUInt().div(n);
    }
}
