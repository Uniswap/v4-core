// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {LockData} from "../types/LockData.sol";

/// @dev This library manages a custom storage implementation for a queue
///      that tracks current lockers. The LOCK_DATA storage slot for this data structure,
///      passed in as a LockData custom type that is a uint256, stores not just the current
///      length of the queue but also the global count of non-zero deltas across all lockers.
///      The values of the data structure start at LOCKERS, and each value is a locker address.
library LockDataLibrary {
    using LockDataLibrary for LockData;

    uint256 private constant LOCK_DATA = uint256(keccak256("LockData"));
    uint256 private constant LOCKERS = uint256(keccak256("Lockers"));

    /// @dev Pushes a locker onto the end of the queue at the LOCKERS + length storage slot, and updates the length at the LOCK_DATA storage slot.
    function push(LockData lockData, address locker) internal {
        // read current length from the LOCK_DATA storage slot
        uint128 _length = lockData.length();
        unchecked {
            uint256 lockerSlot = LOCKERS + _length; // not in assembly because LOCKERS is in the library scope

            /// @solidity memory-safe-assembly
            assembly {
                // in the next storage slot, write the locker
                sstore(lockerSlot, locker)
            }
            lockData.update(_length + 1, lockData.nonzeroDeltaCount());
        }
    }

    /// @dev Pops a locker off the end of the queue. Note that no storage gets cleared.
    function pop(LockData lockData) internal {
        unchecked {
            lockData.update(lockData.length() - 1, lockData.nonzeroDeltaCount());
        }
    }

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

    function update(LockData lockData, uint128 _length, uint128 _nonzeroDeltaCount) internal {
        uint256 lockDataSlot = LOCK_DATA;
        assembly {
            lockData :=
                or(
                    shl(128, _length),
                    and(0x00000000000000000000000000000000ffffffffffffffffffffffffffffffff, _nonzeroDeltaCount)
                )

            sstore(lockDataSlot, lockData)
        }
    }

    function getLock(uint256 i) internal view returns (address locker) {
        unchecked {
            uint256 position = LOCKERS + i; // not in assembly because LOCKERS is in the library scope
            /// @solidity memory-safe-assembly
            assembly {
                locker := sload(position)
            }
        }
    }

    function getActiveLock(LockData lockData) internal view returns (address) {
        uint128 _length;
        unchecked {
            _length = lockData.length() - 1;
        }
        return getLock(_length);
    }

    function getLockData() internal view returns (LockData lockData) {
        uint256 lockDataSlot = LOCK_DATA;
        assembly {
            lockData := sload(lockDataSlot)
        }
    }
}
