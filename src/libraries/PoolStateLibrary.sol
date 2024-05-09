// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {PoolId} from "../types/PoolId.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {Currency} from "../types/Currency.sol";

library PoolStateLibrary {
    // forge inspect src/PoolManager.sol:PoolManager storage --pretty
    // | Name                  | Type                                    | Slot | Offset | Bytes | Contract                        |
    // |-----------------------|-----------------------------------------|------|--------|-------|---------------------------------|
    // | pools                 | mapping(PoolId => struct Pool.State)    | 6    | 0      | 32    | src/PoolManager.sol:PoolManager |
    uint256 public constant POOLS_SLOT = 6;

    // index of feeGrowthGlobal0X128 in Pool.State
    uint256 public constant FEE_GROWTH_GLOBAL0_OFFSET = 1;
    // index of feeGrowthGlobal1X128 in Pool.State
    uint256 public constant FEE_GROWTH_GLOBAL1_OFFSET = 2;

    // index of liquidity in Pool.State
    uint256 public constant LIQUIDITY_OFFSET = 3;

    // index of TicksInfo mapping in Pool.State
    uint256 public constant TICK_INFO_OFFSET = 4;

    // index of tickBitmap mapping in Pool.State
    uint256 public constant TICK_BITMAP_OFFSET = 5;

    // index of Position.Info mapping in Pool.State
    uint256 public constant POSITION_INFO_OFFSET = 6;

    /// uint256(keccak256("ReservesOf")) - 1
    uint256 public constant RESERVES_OF_SLOT =
        uint256(0x1e0745a7db1623981f0b2a5d4232364c00787266eb75ad546f190e6cebe9bd95);

    // The slot holding the number of nonzero deltas. uint256(keccak256("NonzeroDeltaCount")) - 1
    uint256 public constant NONZERO_DELTA_COUNT_SLOT =
        uint256(0x7d4b3164c6e45b97e7d87b7125a44c5828d005af88f9d751cfd78729c5d99a0b);

    // The slot holding the unlocked state, transiently. uint256(keccak256("Unlocked")) - 1;
    uint256 public constant IS_UNLOCKED_SLOT =
        uint256(0xc090fc4683624cfc3884e9d8de5eca132f2d0ec062aff75d43c0465d5ceeab23);

    uint256 public constant ZERO_BALANCE = type(uint256).max;

    /// @notice Thrown when someone has not called sync before calling settle for the first time.
    error ReservesMustBeSynced();

    /**
     * @notice Get Slot0 of the pool: sqrtPriceX96, tick, protocolFee, lpFee
     * @dev Corresponds to pools[poolId].slot0
     * @param manager The pool manager contract.
     * @param poolId The ID of the pool.
     * @return sqrtPriceX96 The square root of the price of the pool, in Q96 precision.
     * @return tick The current tick of the pool.
     * @return protocolFee The protocol fee of the pool.
     * @return lpFee The swap fee of the pool.
     */
    function getSlot0(IPoolManager manager, PoolId poolId)
        internal
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee)
    {
        // slot key of Pool.State value: `pools[poolId]`
        bytes32 stateSlot = _getPoolStateSlot(poolId);

        bytes32 data = manager.extsload(stateSlot);

        //   24 bits  |24bits|24bits      |24 bits|160 bits
        // 0x000000   |000bb8|000000      |ffff75 |0000000000000000fe3aa841ba359daa0ea9eff7
        // ---------- | fee  |protocolfee | tick  | sqrtPriceX96
        assembly {
            // bottom 160 bits of data
            sqrtPriceX96 := and(data, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            // next 24 bits of data
            tick := and(shr(160, data), 0xFFFFFF)
            // next 24 bits of data
            protocolFee := and(shr(184, data), 0xFFFFFF)
            // last 24 bits of data
            lpFee := and(shr(208, data), 0xFFFFFF)
        }
    }

    /**
     * @notice Retrieves the tick information of a pool at a specific tick.
     * @dev Corresponds to pools[poolId].ticks[tick]
     * @param manager The pool manager contract.
     * @param poolId The ID of the pool.
     * @param tick The tick to retrieve information for.
     * @return liquidityGross The total position liquidity that references this tick
     * @return liquidityNet The amount of net liquidity added (subtracted) when tick is crossed from left to right (right to left)
     * @return feeGrowthOutside0X128 fee growth per unit of liquidity on the _other_ side of this tick (relative to the current tick)
     * @return feeGrowthOutside1X128 fee growth per unit of liquidity on the _other_ side of this tick (relative to the current tick)
     */
    function getTickInfo(IPoolManager manager, PoolId poolId, int24 tick)
        internal
        view
        returns (
            uint128 liquidityGross,
            int128 liquidityNet,
            uint256 feeGrowthOutside0X128,
            uint256 feeGrowthOutside1X128
        )
    {
        // slot key of Pool.State value: `pools[poolId]`
        bytes32 stateSlot = _getPoolStateSlot(poolId);

        // Pool.State: `mapping(int24 => TickInfo) ticks`
        bytes32 ticksMapping = bytes32(uint256(stateSlot) + TICK_INFO_OFFSET);

        // slot key of the tick key: `pools[poolId].ticks[tick]
        bytes32 slot = keccak256(abi.encodePacked(int256(tick), ticksMapping));

        // read all 3 words of the TickInfo struct
        bytes memory data = manager.extsload(slot, 3);
        assembly {
            liquidityGross := shr(128, mload(add(data, 32)))
            liquidityNet := and(mload(add(data, 32)), 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            feeGrowthOutside0X128 := mload(add(data, 64))
            feeGrowthOutside1X128 := mload(add(data, 96))
        }
    }

    /**
     * @notice Retrieves the liquidity information of a pool at a specific tick.
     * @dev Corresponds to pools[poolId].ticks[tick].liquidityGross and pools[poolId].ticks[tick].liquidityNet. A more gas efficient version of getTickInfo
     * @param manager The pool manager contract.
     * @param poolId The ID of the pool.
     * @param tick The tick to retrieve liquidity for.
     * @return liquidityGross The total position liquidity that references this tick
     * @return liquidityNet The amount of net liquidity added (subtracted) when tick is crossed from left to right (right to left)
     */
    function getTickLiquidity(IPoolManager manager, PoolId poolId, int24 tick)
        internal
        view
        returns (uint128 liquidityGross, int128 liquidityNet)
    {
        // slot key of Pool.State value: `pools[poolId]`
        bytes32 stateSlot = _getPoolStateSlot(poolId);

        // Pool.State: `mapping(int24 => TickInfo) ticks`
        bytes32 ticksMapping = bytes32(uint256(stateSlot) + TICK_INFO_OFFSET);

        // slot key of the tick key: `pools[poolId].ticks[tick]
        bytes32 slot = keccak256(abi.encodePacked(int256(tick), ticksMapping));

        bytes32 value = manager.extsload(slot);
        assembly {
            liquidityNet := shr(128, value)
            liquidityGross := and(value, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
        }
    }

    /**
     * @notice Retrieves the fee growth outside a tick range of a pool
     * @dev Corresponds to pools[poolId].ticks[tick].feeGrowthOutside0X128 and pools[poolId].ticks[tick].feeGrowthOutside1X128. A more gas efficient version of getTickInfo
     * @param manager The pool manager contract.
     * @param poolId The ID of the pool.
     * @param tick The tick to retrieve fee growth for.
     * @return feeGrowthOutside0X128 fee growth per unit of liquidity on the _other_ side of this tick (relative to the current tick)
     * @return feeGrowthOutside1X128 fee growth per unit of liquidity on the _other_ side of this tick (relative to the current tick)
     */
    function getTickFeeGrowthOutside(IPoolManager manager, PoolId poolId, int24 tick)
        internal
        view
        returns (uint256 feeGrowthOutside0X128, uint256 feeGrowthOutside1X128)
    {
        // slot key of Pool.State value: `pools[poolId]`
        bytes32 stateSlot = _getPoolStateSlot(poolId);

        // Pool.State: `mapping(int24 => TickInfo) ticks`
        bytes32 ticksMapping = bytes32(uint256(stateSlot) + TICK_INFO_OFFSET);

        // slot key of the tick key: `pools[poolId].ticks[tick]
        bytes32 slot = keccak256(abi.encodePacked(int256(tick), ticksMapping));

        // offset by 1 word, since the first word is liquidityGross + liquidityNet
        bytes memory data = manager.extsload(bytes32(uint256(slot) + 1), 2);
        assembly {
            feeGrowthOutside0X128 := mload(add(data, 32))
            feeGrowthOutside1X128 := mload(add(data, 64))
        }
    }

    /**
     * @notice Retrieves the global fee growth of a pool.
     * @dev Corresponds to pools[poolId].feeGrowthGlobal0X128 and pools[poolId].feeGrowthGlobal1X128
     * @param manager The pool manager contract.
     * @param poolId The ID of the pool.
     * @return feeGrowthGlobal0 The global fee growth for token0.
     * @return feeGrowthGlobal1 The global fee growth for token1.
     */
    function getFeeGrowthGlobal(IPoolManager manager, PoolId poolId)
        internal
        view
        returns (uint256 feeGrowthGlobal0, uint256 feeGrowthGlobal1)
    {
        // slot key of Pool.State value: `pools[poolId]`
        bytes32 stateSlot = _getPoolStateSlot(poolId);

        // Pool.State, `uint256 feeGrowthGlobal0X128`
        bytes32 slot_feeGrowthGlobal0X128 = bytes32(uint256(stateSlot) + FEE_GROWTH_GLOBAL0_OFFSET);

        // read the 2 words of feeGrowthGlobal
        bytes memory data = manager.extsload(slot_feeGrowthGlobal0X128, 2);
        assembly {
            feeGrowthGlobal0 := mload(add(data, 32))
            feeGrowthGlobal1 := mload(add(data, 64))
        }
    }

    /**
     * @notice Retrieves total the liquidity of a pool.
     * @dev Corresponds to pools[poolId].liquidity
     * @param manager The pool manager contract.
     * @param poolId The ID of the pool.
     * @return liquidity The liquidity of the pool.
     */
    function getLiquidity(IPoolManager manager, PoolId poolId) internal view returns (uint128 liquidity) {
        // slot key of Pool.State value: `pools[poolId]`
        bytes32 stateSlot = _getPoolStateSlot(poolId);

        // Pool.State: `uint128 liquidity`
        bytes32 slot = bytes32(uint256(stateSlot) + LIQUIDITY_OFFSET);

        liquidity = uint128(uint256(manager.extsload(slot)));
    }

    /**
     * @notice Retrieves the tick bitmap of a pool at a specific tick.
     * @dev Corresponds to pools[poolId].tickBitmap[tick]
     * @param manager The pool manager contract.
     * @param poolId The ID of the pool.
     * @param tick The tick to retrieve the bitmap for.
     * @return tickBitmap The bitmap of the tick.
     */
    function getTickBitmap(IPoolManager manager, PoolId poolId, int16 tick)
        internal
        view
        returns (uint256 tickBitmap)
    {
        // slot key of Pool.State value: `pools[poolId]`
        bytes32 stateSlot = _getPoolStateSlot(poolId);

        // Pool.State: `mapping(int16 => uint256) tickBitmap;`
        bytes32 tickBitmapMapping = bytes32(uint256(stateSlot) + TICK_BITMAP_OFFSET);

        // slot id of the mapping key: `pools[poolId].tickBitmap[tick]
        bytes32 slot = keccak256(abi.encodePacked(int256(tick), tickBitmapMapping));

        tickBitmap = uint256(manager.extsload(slot));
    }

    /**
     * @notice Retrieves the position information of a pool at a specific position ID.
     * @dev Corresponds to pools[poolId].positions[positionId]
     * @param manager The pool manager contract.
     * @param poolId The ID of the pool.
     * @param positionId The ID of the position.
     * @return liquidity The liquidity of the position.
     * @return feeGrowthInside0LastX128 The fee growth inside the position for token0.
     * @return feeGrowthInside1LastX128 The fee growth inside the position for token1.
     */
    function getPositionInfo(IPoolManager manager, PoolId poolId, bytes32 positionId)
        internal
        view
        returns (uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128)
    {
        // slot key of Pool.State value: `pools[poolId]`
        bytes32 stateSlot = _getPoolStateSlot(poolId);

        // Pool.State: `mapping(bytes32 => Position.Info) positions;`
        bytes32 positionMapping = bytes32(uint256(stateSlot) + POSITION_INFO_OFFSET);

        // first value slot of the mapping key: `pools[poolId].positions[positionId] (liquidity)
        bytes32 slot = keccak256(abi.encodePacked(positionId, positionMapping));

        // read all 3 words of the Position.Info struct
        bytes memory data = manager.extsload(slot, 3);

        assembly {
            liquidity := mload(add(data, 32))
            feeGrowthInside0LastX128 := mload(add(data, 64))
            feeGrowthInside1LastX128 := mload(add(data, 96))
        }
    }

    /**
     * @notice Retrieves the liquidity of a position.
     * @dev Corresponds to pools[poolId].positions[positionId].liquidity. A more gas efficient version of getPositionInfo
     * @param manager The pool manager contract.
     * @param poolId The ID of the pool.
     * @param positionId The ID of the position.
     * @return liquidity The liquidity of the position.
     */
    function getPositionLiquidity(IPoolManager manager, PoolId poolId, bytes32 positionId)
        internal
        view
        returns (uint128 liquidity)
    {
        // slot key of Pool.State value: `pools[poolId]`
        bytes32 stateSlot = _getPoolStateSlot(poolId);

        // Pool.State: `mapping(bytes32 => Position.Info) positions;`
        bytes32 positionMapping = bytes32(uint256(stateSlot) + POSITION_INFO_OFFSET);

        // first value slot of the mapping key: `pools[poolId].positions[positionId] (liquidity)
        bytes32 slot = keccak256(abi.encodePacked(positionId, positionMapping));

        liquidity = uint128(uint256(manager.extsload(slot)));
    }

    /**
     * @notice Live calculate the fee growth inside a tick range of a pool
     * @dev pools[poolId].feeGrowthInside0LastX128 in Position.Info is cached and can become stale. This function will live calculate the feeGrowthInside
     * @param manager The pool manager contract.
     * @param poolId The ID of the pool.
     * @param tickLower The lower tick of the range.
     * @param tickUpper The upper tick of the range.
     * @return feeGrowthInside0X128 The fee growth inside the tick range for token0.
     * @return feeGrowthInside1X128 The fee growth inside the tick range for token1.
     */
    function getFeeGrowthInside(IPoolManager manager, PoolId poolId, int24 tickLower, int24 tickUpper)
        internal
        view
        returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128)
    {
        (uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128) = getFeeGrowthGlobal(manager, poolId);

        (uint256 lowerFeeGrowthOutside0X128, uint256 lowerFeeGrowthOutside1X128) =
            getTickFeeGrowthOutside(manager, poolId, tickLower);
        (uint256 upperFeeGrowthOutside0X128, uint256 upperFeeGrowthOutside1X128) =
            getTickFeeGrowthOutside(manager, poolId, tickUpper);
        (, int24 tickCurrent,,) = getSlot0(manager, poolId);
        unchecked {
            if (tickCurrent < tickLower) {
                feeGrowthInside0X128 = lowerFeeGrowthOutside0X128 - upperFeeGrowthOutside0X128;
                feeGrowthInside1X128 = lowerFeeGrowthOutside1X128 - upperFeeGrowthOutside1X128;
            } else if (tickCurrent >= tickUpper) {
                feeGrowthInside0X128 = upperFeeGrowthOutside0X128 - lowerFeeGrowthOutside0X128;
                feeGrowthInside1X128 = upperFeeGrowthOutside1X128 - lowerFeeGrowthOutside1X128;
            } else {
                feeGrowthInside0X128 = feeGrowthGlobal0X128 - lowerFeeGrowthOutside0X128 - upperFeeGrowthOutside0X128;
                feeGrowthInside1X128 = feeGrowthGlobal1X128 - lowerFeeGrowthOutside1X128 - upperFeeGrowthOutside1X128;
            }
        }
    }

    function getReserves(IPoolManager manager, Currency currency) internal view returns (uint256 value) {
        uint256 slot = RESERVES_OF_SLOT;
        bytes32 key;
        assembly {
            mstore(0, slot)
            mstore(32, currency)
            key := keccak256(0, 64)
        }
        value = uint256(manager.exttload(key));
        if (value == 0) revert ReservesMustBeSynced();
        if (value == ZERO_BALANCE) value = 0;
    }

    /// @notice Returns the number of nonzero deltas open on the PoolManager that must be zerod out before the contract is locked
    function getNonzeroDeltaCount(IPoolManager manager) internal view returns (uint256) {
        return uint256(manager.exttload(bytes32(NONZERO_DELTA_COUNT_SLOT)));
    }

    /// @notice Get the current delta for a caller in the given currency
    /// @param caller_ The address of the caller
    /// @param currency The currency for which to lookup the delta
    function currencyDelta(IPoolManager manager, address caller_, Currency currency) external view returns (int256) {
        bytes32 key;
        assembly {
            mstore(0, caller_)
            mstore(32, currency)
            key := keccak256(0, 64)
        }
        return int256(uint256(manager.exttload(key)));
    }

    /// @notice Returns whether the contract is unlocked or not
    function isUnlocked(IPoolManager manager) external view returns (bool) {
        return manager.exttload(bytes32(IS_UNLOCKED_SLOT)) != 0x0;
    }

    function _getPoolStateSlot(PoolId poolId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(PoolId.unwrap(poolId), bytes32(POOLS_SLOT)));
    }
}
