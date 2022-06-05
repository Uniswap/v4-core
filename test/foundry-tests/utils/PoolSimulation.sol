pragma solidity ^0.8.13;

import {Pool} from '../../../contracts/libraries/Pool.sol';
import {TickMath} from '../../../contracts/libraries/TickMath.sol';
import {Random} from './Random.sol';
import {Num} from './Random.sol';

library PoolSimulation {
    using Random for Random.Rand;
    using Num for int256;
    using Num for uint256;

    function addLiquidity(
        Pool.State storage,
        Random.Rand memory rand,
        int24 tickSpacing,
        address sender
    ) internal pure returns (Pool.ModifyPositionParams memory) {
        int24 tick0 = rand.tick(tickSpacing);
        int24 tick1 = rand.tick(tickSpacing);
        if (tick0 == tick1) {
            if (tick1 + tickSpacing < TickMath.MAX_TICK) {
                tick1 += tickSpacing;
            } else {
                tick1 -= tickSpacing;
            }
        }

        // TODO: properly set max bound to max liquidity
        int128 liquidityDelta = int128(
            rand.i256().bound(1, int128(Pool.tickSpacingToMaxLiquidityPerTick(tickSpacing)) / 1000)
        );

        return
            Pool.ModifyPositionParams({
                owner: sender,
                tickLower: tick0 < tick1 ? tick0 : tick1,
                tickUpper: tick0 < tick1 ? tick1 : tick0,
                liquidityDelta: liquidityDelta,
                tickSpacing: tickSpacing
            });
    }

    function swap(
        Pool.State storage pool,
        Random.Rand memory rand,
        int24 tickSpacing
    ) internal view returns (Pool.SwapParams memory) {
        bool zeroForOne = rand.boolean();
        int256 amount = rand.i256().bound(0, type(int256).max);
        uint160 currentPrice = pool.slot0.sqrtPriceX96;
        uint160 sqrtPriceLimitX96 = zeroForOne
            ? uint160(uint256(rand.sqrtPrice()).bound(TickMath.MIN_SQRT_RATIO, currentPrice))
            : uint160(uint256(rand.sqrtPrice()).bound(currentPrice, TickMath.MAX_SQRT_RATIO));

        return
            Pool.SwapParams({
                fee: 0,
                tickSpacing: tickSpacing,
                zeroForOne: zeroForOne,
                amountSpecified: amount,
                sqrtPriceLimitX96: sqrtPriceLimitX96
            });
    }
}
