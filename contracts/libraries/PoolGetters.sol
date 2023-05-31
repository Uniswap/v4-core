// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IPoolManager} from "../interfaces/IPoolManager.sol";

/// @title Helper functions to access pool information
library PoolGetters {
    uint256 constant POOL_SLOT = 4;
    uint256 constant TICKS_OFFSET = 4;
    bytes32 constant MASK_24 = bytes32(uint256((1 << 24) - 1));
    uint256 constant MASK_128 = uint256((1 << 128) - 1);
    uint256 constant MASK_160 = uint256((1 << 160) - 1);

    function getPoolPrice(IPoolManager poolManager, bytes32 poolId) internal returns (uint160 p) {
        bytes32 value = poolManager.extsload(keccak256(abi.encode(poolId, POOL_SLOT)));

        // sqrtPrice = (pool.slot0 & 0xfff..)
        assembly {
            p := and(value, sub(shl(160, 1), 1))
        }
    }

    function getPoolTick(IPoolManager poolManager, bytes32 poolId) internal returns (int24 p) {
        bytes32 value = poolManager.extsload(keccak256(abi.encode(poolId, POOL_SLOT)));

        // tick = (pool.slot0 & 0xffffff << 160) >> 160
        assembly {
            p := shr(160, and(value, shl(160, sub(shl(24, 1), 1))))
        }
    }

    function getGrossLiquidityAtTick(IPoolManager poolManager, bytes32 poolId, int24 tick)
        internal
        returns (uint128 l)
    {
        bytes32 value = poolManager.extsload(
            keccak256(abi.encode(tick, uint256(keccak256(abi.encode(poolId, POOL_SLOT))) + TICKS_OFFSET))
        );

        assembly {
            l := and(value, sub(shl(128, 1), 1))
        }
    }

    function getNetLiquidityAtTick(IPoolManager poolManager, bytes32 poolId, int24 tick) internal returns (int128 l) {
        bytes32 value = poolManager.extsload(
            keccak256(abi.encode(tick, uint256(keccak256(abi.encode(poolId, POOL_SLOT))) + TICKS_OFFSET))
        );

        assembly {
            l := shr(128, and(value, shl(128, sub(shl(128, 1), 1))))
        }
    }

    function getfeeGrowthOutside0AtTick(IPoolManager poolManager, bytes32 poolId, int24 tick)
        internal
        returns (uint256 f)
    {
        f = uint256(
            poolManager.extsload(
                bytes32(
                    uint256(
                        keccak256(abi.encode(tick, uint256(keccak256(abi.encode(poolId, POOL_SLOT))) + TICKS_OFFSET))
                    ) + 1 // second slot in struct
                )
            )
        );
    }

    function getfeeGrowthOutside1AtTick(IPoolManager poolManager, bytes32 poolId, int24 tick)
        internal
        returns (uint256 f)
    {
        f = uint256(
            poolManager.extsload(
                bytes32(
                    uint256(
                        keccak256(abi.encode(tick, uint256(keccak256(abi.encode(poolId, POOL_SLOT))) + TICKS_OFFSET))
                    ) + 2 // third slot in struct
                )
            )
        );
    }
}
