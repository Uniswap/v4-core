// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/console.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";

/// @title Helper functions to access pool information
library PoolGetters {
    uint256 constant POOL_SLOT = 4;
    bytes32 constant MASK_24 = bytes32(uint256((1 << 24) - 1));
    uint256 constant MASK_128 = uint256((1 << 128) - 1);
    bytes32 constant MASK_160 = bytes32(uint256((1 << 160) - 1));

    function getPoolPrice(IPoolManager poolManager, bytes32 poolId) internal returns (uint160) {
        return uint160(
            uint256(
              poolManager.extsload(keccak256(abi.encode(poolId, POOL_SLOT))) & MASK_160
            )
        );
    }

    function getNetLiquidityAtTick(IPoolManager poolManager, bytes32 poolId, int24 tick) internal returns (int128 l) {

        bytes32 value = poolManager.extsload(
          keccak256(abi.encode(tick, uint256(keccak256(abi.encode(poolId, POOL_SLOT))) + 4))
        );

        assembly {
            l := shr(128, and(value, shl(128, sub(shl(128, 1), 1))))
        }
        //
        // console.logBytes32(value);
        // console.logBytes32(value & MASK_128);
        // console.logBytes32(value & (MASK_128 << 128));
        //
        // return int128(int256(uint256(poolManager.extsload(
        //   keccak256(abi.encode(tick, uint256(keccak256(abi.encode(poolId, POOL_SLOT))) + 4))
        // ) & (MASK_128 >> 128))));
    }

}
