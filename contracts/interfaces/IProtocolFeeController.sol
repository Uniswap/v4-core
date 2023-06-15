// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

import {PoolKey} from "../types/PoolKey.sol";

interface IProtocolFeeController {
    /// @notice Returns the protocol fees for a pool given the conditions of this contract
    /// @param poolKey The pool key to identify the pool. The controller may want to use attributes on the pool
    ///   to determine the protocol fee, hence the entire key is needed.
    function protocolFeesForPool(PoolKey memory poolKey) external view returns (uint8, uint8);
}
