// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.9;

import {TickMath} from '../libraries/TickMath.sol';

import {IUniswapV3SwapCallback} from '../interfaces/callback/IUniswapV3SwapCallback.sol';

import {IUniswapV3Pool, IUniswapV3PoolActions} from '../interfaces/IUniswapV3Pool.sol';

contract TestUniswapV3ReentrantCallee is IUniswapV3SwapCallback {
    string private constant expectedReason = 'LOK';

    function swapToReenter(address pool) external {
        IUniswapV3Pool(pool).swap(
            IUniswapV3PoolActions.SwapParameters({
                recipient: address(0),
                zeroForOne: false,
                amountSpecified: 1,
                sqrtPriceLimitX96: TickMath.MAX_SQRT_RATIO - 1,
                data: ''
            })
        );
    }

    function uniswapV3SwapCallback(
        int256,
        int256,
        bytes calldata
    ) external override {
        // try to reenter swap
        try
            IUniswapV3Pool(msg.sender).swap(
                IUniswapV3PoolActions.SwapParameters({
                    recipient: address(0),
                    zeroForOne: false,
                    amountSpecified: 1,
                    sqrtPriceLimitX96: TickMath.MAX_SQRT_RATIO - 1,
                    data: ''
                })
            )
        {} catch Error(string memory reason) {
            require(keccak256(abi.encode(reason)) == keccak256(abi.encode(expectedReason)));
        }

        // try to reenter mint
        try IUniswapV3Pool(msg.sender).mint(address(0), 0, 0, 0, new bytes(0)) {} catch Error(string memory reason) {
            require(keccak256(abi.encode(reason)) == keccak256(abi.encode(expectedReason)));
        }

        // try to reenter collect
        try IUniswapV3Pool(msg.sender).collect(address(0), 0, 0, 0, 0) {} catch Error(string memory reason) {
            require(keccak256(abi.encode(reason)) == keccak256(abi.encode(expectedReason)));
        }

        // try to reenter burn
        try IUniswapV3Pool(msg.sender).burn(0, 0, 0) {} catch Error(string memory reason) {
            require(keccak256(abi.encode(reason)) == keccak256(abi.encode(expectedReason)));
        }

        // try to reenter flash
        try IUniswapV3Pool(msg.sender).flash(address(0), 0, 0, new bytes(0)) {} catch Error(string memory reason) {
            require(keccak256(abi.encode(reason)) == keccak256(abi.encode(expectedReason)));
        }

        // try to reenter collectProtocol
        try IUniswapV3Pool(msg.sender).collectProtocol(address(0), 0, 0) {} catch Error(string memory reason) {
            require(keccak256(abi.encode(reason)) == keccak256(abi.encode(expectedReason)));
        }

        require(false, 'Unable to reenter');
    }
}
