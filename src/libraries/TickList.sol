// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {TickMath} from "./TickMath.sol";

// info stored for each initialized individual tick
struct TickInfo {
    // the total position liquidity that references this tick
    uint128 liquidityGross;
    // amount of net liquidity added (subtracted) when tick is crossed from left to right (right to left),
    int128 liquidityNet;
    // fee growth per unit of liquidity on the _other_ side of this tick (relative to the current tick)
    // only has relative meaning, not absolute — the value depends on when the tick is initialized
    uint256 feeGrowthOutside0X128;
    uint256 feeGrowthOutside1X128;
    // linked list pointers to the next and previous initialized tick
    // Note: must ensure that these are set to min and max tick on the boundaries
    // as the default 0 value is a valid tick
    int24 next;
    int24 prev;
}

/// @title Doubly linked list for initialized ticks
/// @notice Stores a doubly linked list of tick data
library TickList {
    int24 constant NULL_TICK = type(int24).min;

    /// @notice Returns the next initialized tick to the left
    /// (less than or equal to) or right (greater than) of the given tick
    /// @param self The mapping in which to compute the next initialized tick
    /// @param tick The starting tick
    /// @param lte Whether to search for the next initialized tick to the left (less than or equal to the starting tick)
    /// @return nextTick The next initialized or uninitialized tick up to 256 ticks away from the current tick
    function next(mapping(int24 => TickInfo) storage self, int24 tick, bool lte)
        internal
        view
        returns (int24 nextTick)
    {
        nextTick = lte ? self[tick].prev : self[tick].next;

        // If we hit the last initialized tick, set next to the max or min
        if (nextTick == TickList.NULL_TICK) {
            nextTick = lte ? TickMath.MIN_TICK : TickMath.MAX_TICK;
        }
    }
    //
    // function initialize(mapping(int24 => TickInfo) storage self, int24 tick) internal {
    //     self[tick] = TickInfo({
    //         liquidityGross: 0,
    //         liquidityNet: 0,
    //         feeGrowthOutside0X128: 0,
    //         feeGrowthOutside1X128: 0,
    //         next: TickMath.MAX_TICK,
    //         prev: TickMath.MIN_TICK
    //     });
    // }

    /// @notice Adds the given tick to the list
    function insertTick(mapping(int24 => TickInfo) storage self, int24 tick, int24 head)
        internal
        returns (int24 newHead)
    {
        if (head == NULL_TICK) {
            self[tick].next = NULL_TICK;
            self[tick].prev = NULL_TICK;
            return tick;
        }

        if (tick < head) {
            self[tick].next = head;
            self[tick].prev = NULL_TICK;
            self[head].prev = tick;
            return tick;
        }

        int24 curr = head;
        // TODO: use indicative tick from params to improve this
        while (tick > curr) {
            curr = self[curr].next;
        }
        // assume tick != curr since this is only called on a new tick

        self[tick].next = curr;
        int24 prev = self[curr].prev;
        self[tick].prev = prev;
        self[curr].prev = tick;
        self[prev].next = tick;
        return head;
    }

    /// @notice Removes tick data from the list
    /// @param self The mapping containing all initialized tick information for initialized ticks
    /// @param tick The tick that will be cleared
    function removeTick(mapping(int24 => TickInfo) storage self, int24 tick, int24 head)
        internal
        returns (int24 newHead)
    {
        TickInfo memory tickInfo = self[tick];

        if (tickInfo.prev != NULL_TICK) {
            self[tickInfo.prev].next = tickInfo.next;
        } else {
            // we are deleting the head, so new head should be next
            newHead = tickInfo.next;
        }

        if (tickInfo.next != NULL_TICK) {
            self[tickInfo.next].prev = tickInfo.prev;
        }
        delete self[tick];
    }
}
