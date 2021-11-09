// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {Tick} from './libraries/Tick.sol';

import {IUniswapV3PoolImmutables} from './interfaces/pool/IUniswapV3PoolImmutables.sol';
import {IUniswapV3PoolDeployer} from './interfaces/IUniswapV3PoolDeployer.sol';

/// @dev Highly optimized pool proxy contract
contract UniswapV3PoolProxy is IUniswapV3PoolImmutables {
    /// @inheritdoc IUniswapV3PoolImmutables
    address public immutable override factory;

    /// @inheritdoc IUniswapV3PoolImmutables
    address public immutable override token0;

    /// @inheritdoc IUniswapV3PoolImmutables
    address public immutable override token1;

    /// @inheritdoc IUniswapV3PoolImmutables
    uint24 public immutable override fee;

    /// @inheritdoc IUniswapV3PoolImmutables
    int24 public immutable override tickSpacing;

    /// @inheritdoc IUniswapV3PoolImmutables
    uint128 public immutable override maxLiquidityPerTick;

    /// @inheritdoc IUniswapV3PoolImmutables
    function swapImmutables()
        external
        view
        override
        returns (
            address,
            address,
            uint24,
            int24
        )
    {
        return (token0, token1, fee, tickSpacing);
    }

    address private immutable _implementation;

    constructor() {
        _implementation = IUniswapV3PoolDeployer(msg.sender).poolImplementation();

        int24 _tickSpacing;
        (factory, token0, token1, fee, _tickSpacing) = IUniswapV3PoolDeployer(msg.sender).parameters();
        tickSpacing = _tickSpacing;
        maxLiquidityPerTick = Tick.tickSpacingToMaxLiquidityPerTick(_tickSpacing);
    }

    fallback() external {
        address target = _implementation;
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), target, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
}
