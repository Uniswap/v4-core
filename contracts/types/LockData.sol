// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

/// @notice The LockData holds global information for the lock data structure: the length and nonzeroDeltaCount.
/// @dev The left most 128 bits is the length, or total number of active lockers.
/// @dev The right most 128 bits is the nonzeroDeltaCount, or total number of nonzero deltas over all active + completed lockers.
/// @dev Located in transient storage.
/// TODO: With transient storage experiment writing length and nonzeroDeltaCount to two separate slots and compare gas.
type LockData is uint256;

using LockDataLibrary for LockData global;

function toLockData(uint128 _length, uint128 _nonzeroDeltaCount) pure returns (LockData lockData) {
    /// @solidity memory-safe-assembly
    assembly {
        lockData :=
            or(
                shl(128, _length),
                and(0x00000000000000000000000000000000ffffffffffffffffffffffffffffffff, _nonzeroDeltaCount)
            )
    }
}

/// @dev This library manages a custom storage implementation for a queue
///      that tracks current lockers. The LOCK_DATA storage slot for this data structure,
///      passed in as a LockData custom type that is a uint256, stores not just the current
///      length of the queue but also the global count of non-zero deltas across all lockers.
///      The values of the data structure start at LOCKERS, and each value is a locker address.
library LockDataLibrary {
    using LockDataLibrary for LockData;

    uint256 private constant LOCK_DATA_SLOT = uint256(keccak256("LockData"));
    uint256 private constant LOCKERS_SLOT = uint256(keccak256("Lockers"));

    function length(LockData lockData) internal pure returns (uint128 _length) {
        /// @solidity memory-safe-assembly
        assembly {
            _length := shr(128, lockData)
        }
    }

    function nonzeroDeltaCount(LockData lockData) internal pure returns (uint128 _nonzeroDeltaCount) {
        /// @solidity memory-safe-assembly
        assembly {
            _nonzeroDeltaCount := lockData
        }
    }

    /// @dev Pushes a locker onto the end of the queue at the LOCKERS_SLOT + length storage slot, and updates the length at the LOCK_DATA storage slot.
    function push(LockData lockData, address locker) internal {
        // read current length from the LOCK_DATA storage slot
        uint128 _length = lockData.length();
        unchecked {
            uint256 nextLockerSlot = LOCKERS_SLOT + _length; // not in assembly because assembly cannot access constants

            /// @solidity memory-safe-assembly
            assembly {
                // in the next storage slot, write the locker
                tstore(nextLockerSlot, locker)
            }
            LockData newLockData = toLockData(_length + 1, lockData.nonzeroDeltaCount());
            newLockData.update();
        }
    }

    /// @dev Pops a locker off the end of the queue. Note that no storage gets cleared.
    function pop(LockData lockData) internal {
        unchecked {
            LockData newLockData = toLockData(lockData.length() - 1, lockData.nonzeroDeltaCount());
            newLockData.update();
        }
    }

    /// @dev Decreases the nonzero delta count by 1.
    function decrementNonzeroDeltaCount(LockData lockData) internal {
        uint256 newLockData;
        unchecked {
            newLockData = LockData.unwrap(lockData) - 1;
        }
        LockData.wrap(newLockData).update();
    }

    /// @dev Increases the nonzero delta count by 1.
    function incrementNonzeroDeltaCount(LockData lockData) internal {
        uint256 newLockData;
        unchecked {
            newLockData = LockData.unwrap(lockData) + 1;
        }
        LockData.wrap(newLockData).update();
    }

    /// @dev Clears the length and nonzero delta count from the lockData.
    function clear() internal {
        LockData lockData = LockData.wrap(uint256(0));
        lockData.update();
    }

    /// @dev Writes the new length and nonzeroDeltaCount to storage.
    /// TODO: Use transient storage.
    function update(LockData lockData) internal {
        uint256 lockDataSlot = LOCK_DATA_SLOT;
        assembly {
            tstore(lockDataSlot, lockData)
        }
    }

    /// @dev Returns the locker at the ith  index.
    /// TODO: Use transient storage.
    function getLock(uint256 i) internal view returns (address locker) {
        unchecked {
            uint256 position = LOCKERS_SLOT + i; // not in assembly because assembly can't read constants
            /// @solidity memory-safe-assembly
            assembly {
                locker := tload(position)
            }
        }
    }

    /// @dev Returns the current locker.
    function getActiveLock(LockData lockData) internal view returns (address) {
        uint128 _length;
        unchecked {
            _length = lockData.length() - 1;
        }
        return getLock(_length);
    }

    /// @dev Returns the current length and nonzeroDeltaCount.
    /// TODO: Use transient storage.
    function getLockData() internal view returns (LockData lockData) {
        uint256 lockDataSlot = LOCK_DATA_SLOT;
        assembly {
            lockData := tload(lockDataSlot)
        }
    }
}
