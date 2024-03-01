// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {IHooks} from "../interfaces/IHooks.sol";

/// @notice This is a temporary library that allows us to use transient storage (tstore/tload)
/// for the lockers array
/// TODO: This library can be deleted when we have the transient keyword support in solidity.
library Locker {
    // The slot holding the locker, transiently, and the lock caller in the next slot
    uint256 constant LOCKER_SLOT = uint256(keccak256("Locker")) - 1;

    /// @notice Thrown when trying to set the lock target as address(0)
    /// we use locker==address(0) to signal that the pool is not locked
    error InvalidLocker();

    function lock() internal {
        uint256 slot = LOCKER_SLOT;
        assembly {
            // set the lock
            tstore(slot, true)
        }
    }

    function unlock() internal {
        uint256 slot = LOCKER_SLOT;
        assembly {
            tstore(slot, false)
        }
    }

    function isLocked() internal view returns (bool locked) {
        uint256 slot = LOCKER_SLOT;
        assembly {
            locked := tload(slot)
        }
    }
}
