// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {IPoolManager} from './IPoolManager.sol';

interface IProtocolFeeController {
    function protocolFeeForPool(bytes32 id) external view returns (uint8);
}
