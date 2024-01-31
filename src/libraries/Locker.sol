// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {IHooks} from "../interfaces/IHooks.sol";

/// @notice This is a temporary library that allows us to use transient storage (tstore/tload)
/// for the lockers array
/// TODO: This library can be deleted when we have the transient keyword support in solidity.
library Locker {
    // The slot holding the locker, transiently, and the lock caller in the next slot
    uint256 constant LOCKER_SLOT = uint256(keccak256("Locker")) - 2;
    uint256 constant LOCK_CALLER_SLOT = LOCKER_SLOT + 1;

    function setLockerAndCaller(address locker, address lockCaller) internal {
        uint256 slot = LOCKER_SLOT;

        assembly {
            // set the locker
            tstore(slot, locker)

            // set the lock caller
            tstore(add(slot, 1), lockCaller)
        }
    }

    function clearLockerAndCaller() internal {
        uint256 slot = LOCKER_SLOT;
        assembly {
            tstore(slot, 0)
            tstore(add(slot, 1), 0)
        }
    }

    function getLocker() internal view returns (address locker) {
        uint256 slot = LOCKER_SLOT;
        assembly {
            locker := tload(slot)
        }
    }

    function isLocked() internal view returns (bool) {
        return Locker.getLockCaller() != address(0);
    }

    function getLockCaller() internal view returns (address locker) {
        uint256 slot = LOCK_CALLER_SLOT;
        assembly {
            locker := tload(slot)
        }
    }
}
