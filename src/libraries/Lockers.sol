// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {IHooks} from "../interfaces/IHooks.sol";

/// @notice This is a temporary library that allows us to use transient storage (tstore/tload)
/// for the lockers array and nonzero delta count.
/// TODO: This library can be deleted when we have the transient keyword support in solidity.
library Lockers {
    // The starting slot for an array of lockers, stored transiently.
    uint256 constant LOCKERS_SLOT = uint256(keccak256("Lockers")) - 1;

    // The number of slots per item in the lockers array
    uint256 constant LOCKER_STRUCT_SIZE = 2;

    // The starting slot for an array of hook addresses per locker, stored transiently.
    uint256 constant HOOK_ADDRESS_SLOT = uint256(keccak256("HookAddress")) - 1;

    // The slot holding the number of nonzero deltas.
    uint256 constant NONZERO_DELTA_COUNT = uint256(keccak256("NonzeroDeltaCount")) - 1;

    // pushes an address tuple (address locker, address lockCaller)
    // to the locker array, so each length of the array represents 2 slots of tstorage
    function push(address locker, address lockCaller) internal {
        uint256 slot = LOCKERS_SLOT;

        uint256 newLength;
        uint256 thisLockerSlot;

        unchecked {
            newLength = length() + 1;
            thisLockerSlot = LOCKERS_SLOT + (newLength * LOCKER_STRUCT_SIZE);
        }

        assembly {
            // add the locker
            tstore(thisLockerSlot, locker)

            // add the lock caller
            tstore(add(thisLockerSlot, 1), lockCaller)

            // increase the length
            tstore(slot, newLength)
        }
    }

    function pop() internal {
        // decrease the length
        uint256 slot = LOCKERS_SLOT;
        uint256 newLength;
        unchecked {
            newLength = length() - 1;
        }
        assembly {
            tstore(slot, newLength)
        }
    }

    function length() internal view returns (uint256 _length) {
        uint256 slot = LOCKERS_SLOT;
        assembly {
            _length := tload(slot)
        }
    }

    function clear() internal {
        uint256 slot = LOCKERS_SLOT;
        assembly {
            tstore(slot, 0)
        }
    }

    function getLocker(uint256 i) internal view returns (address locker) {
        // first slot of the ith array item
        uint256 slot = LOCKERS_SLOT + (i * LOCKER_STRUCT_SIZE);
        assembly {
            locker := tload(slot)
        }
    }

    function getLockCaller(uint256 i) internal view returns (address locker) {
        // second slot of the ith array item
        uint256 slot = LOCKERS_SLOT + (i * LOCKER_STRUCT_SIZE + 1);
        assembly {
            locker := tload(slot)
        }
    }

    function getCurrentLocker() internal view returns (address locker) {
        return getLocker(length());
    }

    function getCurrentLockCaller() internal view returns (address locker) {
        return getLockCaller(length());
    }

    function nonzeroDeltaCount() internal view returns (uint256 count) {
        uint256 slot = NONZERO_DELTA_COUNT;
        assembly {
            count := tload(slot)
        }
    }

    function incrementNonzeroDeltaCount() internal {
        uint256 slot = NONZERO_DELTA_COUNT;
        assembly {
            let count := tload(slot)
            count := add(count, 1)
            tstore(slot, count)
        }
    }

    /// @notice Potential to underflow.
    /// Current usage ensures this will not happen because we call decrememnt with known boundaries (only up to the numer of times we call increment).
    function decrementNonzeroDeltaCount() internal {
        uint256 slot = NONZERO_DELTA_COUNT;
        assembly {
            let count := tload(slot)
            count := sub(count, 1)
            tstore(slot, count)
        }
    }

    function getCurrentHook() internal view returns (IHooks currentHook) {
        return IHooks(getHook(length()));
    }

    function getHook(uint256 i) internal view returns (address hook) {
        uint256 slot = HOOK_ADDRESS_SLOT + i;
        assembly {
            hook := tload(slot)
        }
    }

    function setCurrentHook(IHooks currentHook) internal returns (bool set) {
        // Set the hook address for the current locker if the address is 0.
        // If the address is nonzero, a hook has already been set for this lock, and is not allowed to be updated or cleared at the end of the call.
        if (address(getCurrentHook()) == address(0)) {
            uint256 slot = HOOK_ADDRESS_SLOT + length();
            assembly {
                tstore(slot, currentHook)
            }
            return true;
        }
    }

    function clearCurrentHook() internal {
        uint256 slot = HOOK_ADDRESS_SLOT + length();
        assembly {
            tstore(slot, 0)
        }
    }
}
