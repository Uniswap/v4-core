// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PoolKey} from "../types/PoolKey.sol";

/// @notice Interface to fetch the protocol fees for a pool from the protocol fee controller
interface IProtocolFeeController {
    /// @notice Returns the protocol fees for a pool given the conditions of this contract
    /// @param poolKey The pool key to identify the pool. The controller may want to use attributes on the pool
    ///   to determine the protocol fee, hence the entire key is needed.
    /// @return protocolFee The pool's protocol fee, expressed in hundredths of a bip. The upper 12 bits are for 1->0
    /// and the lower 12 are for 0->1. The maximum is 1000 - meaning the maximum protocol fee is 0.1%.
    /// the protocolFee is taken from the input first, then the lpFee is taken from the remaining input
    function protocolFeeForPool(PoolKey memory poolKey) external view returns (uint24 protocolFee);
}
