// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {IPoolManager} from './IPoolManager.sol';

interface IProtocolFeeController {
    /// @notice Returns the protocol call fee for a pool given the conditions of this contract
    /// @param key The pool key to identify the pool. The controller may want to use attributes on the pool
    ///   to determine the protocol fee, hence the entire key is needed.
    function protocolFeeForPool(IPoolManager.PoolKey memory key) external view returns (uint8);
}
