// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PoolKey} from "./PoolKey.sol";

type PoolId is bytes32;

/// @notice Library for computing the ID of a pool
library PoolIdLibrary {
    /// @notice Returns value equal to keccak256(abi.encode(poolKey))
    function toId(PoolKey memory poolKey) internal pure returns (PoolId poolId) {
        assembly ("memory-safe") {
            poolId := keccak256(poolKey, mul(32, 5))
        }
    }
}
