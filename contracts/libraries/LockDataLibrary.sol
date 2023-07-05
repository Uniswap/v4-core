// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {IPoolManager} from "../interfaces/IPoolManager.sol";

/// @dev This library manages a custom storage implementation for a queue
///      that tracks current lockers.
///      The "sentinel" storage slot for this data structure, always passed in as
///      IPoolManager.LockData storage self, stores not just the current length
///      of the queue, but also two other variables: the index of the current
///      locker and the global count of non-zero deltas across all lockers.
///      The values of the data structure start at OFFSET, and each value is itself
///      packed data of: locker address (160 bits) and the parent lock index (96 bits)
library LockDataLibrary {
    uint256 private constant OFFSET = uint256(keccak256("LockData"));

    /// @dev Pushes an element onto the end of the queue, and updates the sentinel
    ///      storage slot accordingly.
    function push(IPoolManager.LockData storage self, address locker) internal {
        // read current values from the sentinel storage slot
        uint96 length = self.length;
        uint256 index = self.index; // only 96 bits, but we expand for clarity with the bitwise or below

        unchecked {
            uint256 indexToWrite = OFFSET + length; // not in assembly because OFFSET is in the library scope
            /// @solidity memory-safe-assembly
            assembly {
                // in the next storage slot, write the packed locker and parent index
                sstore(indexToWrite, or(shl(96, locker), index))
            }
            self.length = length + 1;
            self.index = length; // the pushed element is now active
        }
    }

    /// @dev Pops an element off the end of the queue. Note that no storage gets cleared,
    ///      but the active index in the sentinel storage slot is updated.
    function pop(IPoolManager.LockData storage self) internal {
        (, uint96 parentLockIndex) = getActiveLock(self);
        self.index = parentLockIndex;
    }

    function getLock(uint256 i) internal view returns (address locker, uint96 parentLockIndex) {
        unchecked {
            uint256 position = OFFSET + i;
            /// @solidity memory-safe-assembly
            assembly {
                let value := sload(position)
                // unpack values
                locker := shr(96, value)
                parentLockIndex := and(0x0000000000000000000000000000000000000000ffffffffffffffffffffffff, value)
            }
        }
    }

    function getActiveLock(IPoolManager.LockData storage self)
        internal
        view
        returns (address locker, uint96 parentLockIndex)
    {
        return getLock(self.index);
    }
}
