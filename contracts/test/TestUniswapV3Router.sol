// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.9;

import {SafeCast} from '../libraries/SafeCast.sol';
import {TickMath} from '../libraries/TickMath.sol';

import {IERC20Minimal} from '../interfaces/IERC20Minimal.sol';
import {IUniswapV3SwapCallback} from '../interfaces/callback/IUniswapV3SwapCallback.sol';
import {IUniswapV3Pool, IUniswapV3PoolActions} from '../interfaces/IUniswapV3Pool.sol';

contract TestUniswapV3Router is IUniswapV3SwapCallback {
    using SafeCast for uint256;

    // flash swaps for an exact amount of token0 in the output pool
    function swapForExact0Multi(
        address recipient,
        address poolInput,
        address poolOutput,
        uint256 amount0Out
    ) external {
        address[] memory pools = new address[](1);
        pools[0] = poolInput;
        IUniswapV3Pool(poolOutput).swap(
            IUniswapV3PoolActions.SwapParameters({
                recipient: recipient,
                zeroForOne: false,
                amountSpecified: -amount0Out.toInt256(),
                sqrtPriceLimitX96: TickMath.MAX_SQRT_RATIO - 1,
                data: abi.encode(pools, msg.sender)
            })
        );
    }

    // flash swaps for an exact amount of token1 in the output pool
    function swapForExact1Multi(
        address recipient,
        address poolInput,
        address poolOutput,
        uint256 amount1Out
    ) external {
        address[] memory pools = new address[](1);
        pools[0] = poolInput;
        IUniswapV3Pool(poolOutput).swap(
            IUniswapV3PoolActions.SwapParameters({
                recipient: recipient,
                zeroForOne: true,
                amountSpecified: -amount1Out.toInt256(),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_RATIO + 1,
                data: abi.encode(pools, msg.sender)
            })
        );
    }

    event SwapCallback(int256 amount0Delta, int256 amount1Delta);

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) public override {
        emit SwapCallback(amount0Delta, amount1Delta);

        (address[] memory pools, address payer) = abi.decode(data, (address[], address));

        if (pools.length == 1) {
            // get the address and amount of the token that we need to pay
            address tokenToBePaid = amount0Delta > 0
                ? IUniswapV3Pool(msg.sender).token0()
                : IUniswapV3Pool(msg.sender).token1();
            int256 amountToBePaid = amount0Delta > 0 ? amount0Delta : amount1Delta;

            bool zeroForOne = tokenToBePaid == IUniswapV3Pool(pools[0]).token1();
            IUniswapV3Pool(pools[0]).swap(
                IUniswapV3PoolActions.SwapParameters({
                    recipient: msg.sender,
                    zeroForOne: zeroForOne,
                    amountSpecified: -amountToBePaid,
                    sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
                    data: abi.encode(new address[](0), payer)
                })
            );
        } else {
            if (amount0Delta > 0) {
                IERC20Minimal(IUniswapV3Pool(msg.sender).token0()).transferFrom(
                    payer,
                    msg.sender,
                    uint256(amount0Delta)
                );
            } else {
                IERC20Minimal(IUniswapV3Pool(msg.sender).token1()).transferFrom(
                    payer,
                    msg.sender,
                    uint256(amount1Delta)
                );
            }
        }
    }
}
