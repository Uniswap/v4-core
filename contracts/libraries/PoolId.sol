// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

import {IPoolManager} from "../interfaces/IPoolManager.sol";

/// @notice Library for computing the ID of a pool
library PoolId {
    function toId(IPoolManager.PoolKey memory poolKey) internal pure returns (bytes32) {
        return keccak256(abi.encode(poolKey));
    }
}
