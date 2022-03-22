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
        bytes16 secondsElapsed;
    }

    /// @notice Calculation used incrementally (b/w expiration intervals or initialized ticks)
    ///    to calculate earnings rewards and the amm price change resulting from executing TWAMM orders
    function calculateExecutionUpdates(
        uint256 secondsElapsed,
        TWAMM.PoolParamsOnExecute memory poolParams,
        TWAMM.OrderPoolParamsOnExecute memory orderPoolParams,
        mapping(int24 => Tick.Info) storage ticks
    )
        internal
        pure
        returns (
            uint160 sqrtPriceX96,
            uint256 earningsPool0,
            uint256 earningsPool1
        )
    {
        // https://www.desmos.com/calculator/yr3qvkafvy
        // https://www.desmos.com/calculator/rjcdwnaoja -- tracks some intermediate calcs
        // TODO:
        // -- Need to incorporate ticks
        // -- perform calcs when a sellpool is 0
        // -- update TWAP

        ParamsBytes16 memory params = ParamsBytes16({
            sqrtPriceX96: poolParams.sqrtPriceX96.fromUInt(),
            liquidity: poolParams.liquidity.fromUInt(),
            sellRateCurrent0: orderPoolParams.sellRateCurrent0.fromUInt(),
            sellRateCurrent1: orderPoolParams.sellRateCurrent1.fromUInt(),
            secondsElapsed: secondsElapsed.fromUInt()
        });

        bytes16 sellRatio = params.sellRateCurrent1.div(params.sellRateCurrent0);

        bytes16 sqrtSellRatioX96 = sellRatio.sqrt().mul(Q96);

        bytes16 sqrtSellRate = params.sellRateCurrent0.mul(params.sellRateCurrent1).sqrt();

        bytes16 newSqrtPriceX96 = calculateNewSqrtPriceX96(
            sqrtSellRatioX96,
            sqrtSellRate,
            params.secondsElapsed,
            params
        );

        EarningsFactorParams memory earningsFactorParams = EarningsFactorParams({
            secondsElapsed: params.secondsElapsed,
            sellRatio: sellRatio,
            sqrtSellRate: sqrtSellRate,
            prevSqrtPriceX96: params.sqrtPriceX96,
            newSqrtPriceX96: newSqrtPriceX96,
            liquidity: params.liquidity
        });

        sqrtPriceX96 = newSqrtPriceX96.toUInt().toUint160();
        earningsPool0 = getEarningsAmountPool0(earningsFactorParams).toUInt();
        earningsPool1 = getEarningsAmountPool1(earningsFactorParams).toUInt();
    }

    /// @notice Used when crossing an initialized tick. Can extract the amount of seconds it took to cross
    ///   the tick, and recalibrate the calculation from there to accommodate liquidity changes
    function calculateTimeBetweenTicks(
        bytes16 liquidity,
        bytes16 sqrtPriceStartX96,
        bytes16 sqrtPriceEndX96,
        bytes16 sqrtSellRate,
        bytes16 sqrtSellRatioX96
    ) internal view returns (bytes16 secondsBetween) {
        bytes16 numpt1 = sqrtSellRatioX96.add(sqrtPriceEndX96).div(sqrtSellRatioX96.sub(sqrtPriceEndX96));
        bytes16 numpt2 = sqrtSellRatioX96.sub(sqrtPriceStartX96).div(sqrtSellRatioX96.add(sqrtPriceStartX96));
        bytes16 numerator = numpt1.mul(numpt2).ln().mul(liquidity);
        bytes16 denominator = uint256(2).fromUInt().mul(sqrtSellRate);
        return numerator.div(denominator);
    }

    struct EarningsFactorParams {
        bytes16 secondsElapsed;
        bytes16 sellRatio;
        bytes16 sqrtSellRate;
        bytes16 prevSqrtPriceX96;
        bytes16 newSqrtPriceX96;
        bytes16 liquidity;
    }

    function getEarningsAmountPool0(EarningsFactorParams memory params) private pure returns (bytes16 earningsFactor) {
        bytes16 minuend = params.sellRatio.mul(Q96).mul(params.secondsElapsed);
        bytes16 subtrahend = params
            .liquidity
            .mul(params.sellRatio.sqrt())
            .mul(params.newSqrtPriceX96.sub(params.prevSqrtPriceX96))
            .div(params.sqrtSellRate);
        return minuend.sub(subtrahend);
    }

    function getEarningsAmountPool1(EarningsFactorParams memory params) private pure returns (bytes16 earningsFactor) {
        bytes16 minuend = params.secondsElapsed.div(params.sellRatio);
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
        bytes16 secondsElapsed,
        ParamsBytes16 memory params
    ) private pure returns (bytes16 newSqrtPriceX96) {
        bytes16 pow = uint256(2).fromUInt().mul(sqrtSellRate).mul(secondsElapsed).div(params.liquidity);
        bytes16 c = sqrtSellRatioX96.sub(params.sqrtPriceX96).div(sqrtSellRatioX96.add(params.sqrtPriceX96));
        newSqrtPriceX96 = sqrtSellRatioX96.mul(pow.exp().sub(c)).div(pow.exp().add(c));
    }

    function reciprocal(bytes16 n) private pure returns (bytes16) {
        return uint256(1).fromUInt().div(n);
    }

    function calculateCancellationAmounts(
        TWAMM.Order memory order,
        uint256 earningsFactorCurrent,
        uint256 timestamp
    ) internal view returns (uint256 unsoldAmount, uint256 purchasedAmount) {
        unsoldAmount = order.sellRate * (order.expiration - timestamp);
        uint256 earningsFactor = (earningsFactorCurrent - order.unclaimedEarningsFactor);
        purchasedAmount = (earningsFactor * order.sellRate) >> FixedPoint96.RESOLUTION;
    }
}
