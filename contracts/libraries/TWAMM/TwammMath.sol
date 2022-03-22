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

        bytes16 sellRatio = orderPoolParams.sellRateCurrent1.fromUInt().div(
            orderPoolParams.sellRateCurrent0.fromUInt()
        );

        bytes16 sqrtSellRate = orderPoolParams
            .sellRateCurrent0
            .fromUInt()
            .mul(orderPoolParams.sellRateCurrent1.fromUInt())
            .sqrt();

        bytes16 newSqrtPriceX96 = calculateNewSqrtPriceX96(sellRatio, sqrtSellRate, secondsElapsed, poolParams);

        EarningsFactorParams memory earningsFactorParams = EarningsFactorParams({
            secondsElapsed: secondsElapsed.fromUInt(),
            sellRatio: sellRatio,
            sqrtSellRate: sqrtSellRate,
            prevSqrtPriceX96: poolParams.sqrtPriceX96.fromUInt(),
            newSqrtPriceX96: newSqrtPriceX96,
            liquidity: poolParams.liquidity.fromUInt()
        });

        sqrtPriceX96 = newSqrtPriceX96.toUInt().toUint160();
        earningsPool0 = getEarningsAmountPool0(earningsFactorParams).toUInt();
        earningsPool1 = getEarningsAmountPool1(earningsFactorParams).toUInt();
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
        bytes16 minuend = params.sellRatio.mul(FixedPoint96.Q96.fromUInt()).mul(params.secondsElapsed);
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
            .mul(
                reciprocal(params.newSqrtPriceX96).mul(FixedPoint96.Q96.fromUInt()).sub(
                    reciprocal(params.prevSqrtPriceX96).mul(FixedPoint96.Q96.fromUInt())
                )
            )
            .div(params.sqrtSellRate);
        return minuend.sub(subtrahend).mul(FixedPoint96.Q96.fromUInt());
    }

    function calculateNewSqrtPriceX96(
        bytes16 sellRatio,
        bytes16 sqrtSellRate,
        uint256 secondsElapsed,
        TWAMM.PoolParamsOnExecute memory poolParams
    ) private pure returns (bytes16 newSqrtPriceX96) {
        bytes16 sqrtSellRatioX96 = sellRatio.sqrt().mul(FixedPoint96.Q96.fromUInt());

        bytes16 pow = uint256(2).fromUInt().mul(sqrtSellRate).mul((secondsElapsed).fromUInt()).div(
            poolParams.liquidity.fromUInt()
        );

        bytes16 c = sqrtSellRatioX96.sub(poolParams.sqrtPriceX96.fromUInt()).div(
            sqrtSellRatioX96.add(poolParams.sqrtPriceX96.fromUInt())
        );

        newSqrtPriceX96 = sqrtSellRatioX96.mul(pow.exp().sub(c)).div(pow.exp().add(c));
    }

    function reciprocal(bytes16 n) private pure returns (bytes16) {
        return uint256(1).fromUInt().div(n);
    }
}
