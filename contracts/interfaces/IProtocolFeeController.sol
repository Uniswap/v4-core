// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {IPoolManager} from './IPoolManager.sol';

interface IProtocolFeeController {
    function fetchInitialFee(IPoolManager.PoolKey memory key) external view returns (uint8);
}