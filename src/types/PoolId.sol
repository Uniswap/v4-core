// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PoolKey} from "./PoolKey.sol";

/// @title PoolId
/// @notice A unique identifier for a Uniswap v4 pool, derived from its PoolKey
/// @dev PoolId is the keccak256 hash of the PoolKey struct, providing a gas-efficient
/// way to identify and store pool data. This is used as the key in mappings throughout
/// the PoolManager for O(1) pool lookups.
type PoolId is bytes32;

/// @notice Library for computing the ID of a pool
/// @dev Provides a gas-optimized method to derive the PoolId from a PoolKey
library PoolIdLibrary {
    /// @notice Computes the unique identifier for a pool given its key
    /// @dev Returns value equal to keccak256(abi.encode(poolKey))
    /// Uses assembly for gas efficiency, computing the hash directly from memory.
    /// @param poolKey The PoolKey struct containing pool configuration
    /// @return poolId The unique bytes32 identifier for the pool
    function toId(PoolKey memory poolKey) internal pure returns (PoolId poolId) {
        assembly ("memory-safe") {
            // 0xa0 (160 bytes) represents the total size of the poolKey struct:
            // - currency0: 32 bytes (address padded to 32)
            // - currency1: 32 bytes (address padded to 32)
            // - fee: 32 bytes (uint24 padded to 32)
            // - tickSpacing: 32 bytes (int24 padded to 32)
            // - hooks: 32 bytes (address padded to 32)
            poolId := keccak256(poolKey, 0xa0)
        }
    }
}
