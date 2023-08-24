// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {PoolKey} from "./PoolKey.sol";

type PoolId is bytes32;

/// @notice Library for computing the ID of a pool
library PoolIdLibrary {
    function toId(PoolKey memory poolKey) internal pure returns (PoolId poolId) {
        assembly("memory-safe") {
            poolId := keccak256(poolKey,mul(32,5))
        }
    }
}
