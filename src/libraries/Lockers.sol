// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/// @notice This is a temporary library that allows us to use transient storage (tstore/tload)
/// for the lockers array and nonzero delta count.
/// TODO: This library can be deleted when we have the transient keyword support in solidity.
library Lockers {
    // The starting slot for an array of lockers, stored transiently.
    uint256 constant LOCKERS_SLOT = uint256(keccak256("Lockers")) - 1;

    // The slot holding the number of nonzero deltas.
    uint256 constant NONZERO_DELTA_COUNT = uint256(keccak256("NonzeroDeltaCount")) - 1;

    function push(address locker) internal {
        uint256 slot = LOCKERS_SLOT;

        uint256 newLength;
        uint256 thisLockerSlot;

        unchecked {
            newLength = length() + 1;
            thisLockerSlot = LOCKERS_SLOT + newLength;
        }

        assembly {
            // add the locker
            tstore(thisLockerSlot, locker)

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
        uint256 slot = LOCKERS_SLOT + i;
        assembly {
            locker := tload(slot)
        }
    }

    function getCurrentLocker() internal view returns (address locker) {
        return getLocker(length());
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
    /// Current useage ensures this will not happen because we call decrememnt with known boundaries (only up to the numer of times we call increment).
    function decrementNonzeroDeltaCount() internal {
        uint256 slot = NONZERO_DELTA_COUNT;
        assembly {
            let count := tload(slot)
            count := sub(count, 1)
            tstore(slot, count)
        }
    }
}
