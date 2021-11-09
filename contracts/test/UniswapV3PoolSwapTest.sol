// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.9;

import {IERC20Minimal} from '../interfaces/IERC20Minimal.sol';

import {IUniswapV3SwapCallback} from '../interfaces/callback/IUniswapV3SwapCallback.sol';
import {IUniswapV3Pool, IUniswapV3PoolActions} from '../interfaces/IUniswapV3Pool.sol';

contract UniswapV3PoolSwapTest is IUniswapV3SwapCallback {
    int256 private _amount0Delta;
    int256 private _amount1Delta;

    function getSwapResult(
        address pool,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    )
        external
        returns (
            int256 amount0Delta,
            int256 amount1Delta,
            uint160 nextSqrtRatio
        )
    {
        (amount0Delta, amount1Delta) = IUniswapV3Pool(pool).swap(
            IUniswapV3PoolActions.SwapParameters({
                recipient: address(0),
                zeroForOne: zeroForOne,
                amountSpecified: amountSpecified,
                sqrtPriceLimitX96: sqrtPriceLimitX96,
                data: abi.encode(msg.sender)
            })
        );

        (nextSqrtRatio, , , , , , ) = IUniswapV3Pool(pool).slot0();
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        address sender = abi.decode(data, (address));

        if (amount0Delta > 0) {
            IERC20Minimal(IUniswapV3Pool(msg.sender).token0()).transferFrom(sender, msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            IERC20Minimal(IUniswapV3Pool(msg.sender).token1()).transferFrom(sender, msg.sender, uint256(amount1Delta));
        }
    }
}
