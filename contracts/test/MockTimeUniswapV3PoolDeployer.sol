// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.9;

import {UniswapV3PoolDeployer} from '../UniswapV3PoolDeployer.sol';

contract MockTimeUniswapV3PoolDeployer is UniswapV3PoolDeployer {
    constructor(address _poolImplementation) UniswapV3PoolDeployer(_poolImplementation) {}

    function createPool(
        address factory,
        address token0,
        address token1,
        uint24 fee,
        int24 tickSpacing
    ) external returns (address pool) {
        return deploy(factory, token0, token1, fee, tickSpacing);
    }
}
