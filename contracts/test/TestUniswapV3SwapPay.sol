// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.9;

import {IERC20Minimal} from '../interfaces/IERC20Minimal.sol';

import {IUniswapV3SwapCallback} from '../interfaces/callback/IUniswapV3SwapCallback.sol';
import {IUniswapV3Pool, IUniswapV3PoolActions} from '../interfaces/IUniswapV3Pool.sol';

contract TestUniswapV3SwapPay is IUniswapV3SwapCallback {
    function swap(
        address pool,
        address recipient,
        bool zeroForOne,
        uint160 sqrtPriceLimitX96,
        int256 amountSpecified,
        uint256 pay0,
        uint256 pay1
    ) external {
        IUniswapV3Pool(pool).swap(
            IUniswapV3PoolActions.SwapParameters({
                recipient: recipient,
                zeroForOne: zeroForOne,
                amountSpecified: amountSpecified,
                sqrtPriceLimitX96: sqrtPriceLimitX96,
                data: abi.encode(msg.sender, pay0, pay1)
            })
        );
    }

    function uniswapV3SwapCallback(
        int256,
        int256,
        bytes calldata data
    ) external override {
        (address sender, uint256 pay0, uint256 pay1) = abi.decode(data, (address, uint256, uint256));

        if (pay0 > 0) {
            IERC20Minimal(IUniswapV3Pool(msg.sender).token0()).transferFrom(sender, msg.sender, uint256(pay0));
        } else if (pay1 > 0) {
            IERC20Minimal(IUniswapV3Pool(msg.sender).token1()).transferFrom(sender, msg.sender, uint256(pay1));
        }
    }
}
