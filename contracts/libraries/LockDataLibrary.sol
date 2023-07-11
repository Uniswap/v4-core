// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {IPoolManager} from "../interfaces/IPoolManager.sol";

/// @dev This library manages a custom storage implementation for a queue
///      that tracks current lockers. The "sentinel" storage slot for this data structure,
///      always passed in as IPoolManager.LockData storage self, stores not just the current
///      length of the queue but also the global count of non-zero deltas across all lockers.
///      The values of the data structure start at OFFSET, and each value is a locker address.
library LockDataLibrary {
    uint256 private constant OFFSET = uint256(keccak256("LockData"));

    /// @dev Pushes a locker onto the end of the queue, and updates the sentinel storage slot.
    function push(IPoolManager.LockData storage self, address locker) internal {
        // read current value from the sentinel storage slot
        uint128 length = self.length;
        unchecked {
            uint256 indexToWrite = OFFSET + length; // not in assembly because OFFSET is in the library scope
            /// @solidity memory-safe-assembly
            assembly {
                // in the next storage slot, write the locker
                sstore(indexToWrite, locker)
            }
            // update the sentinel storage slot
            self.length = length + 1;
        }
    }

    /// @dev Pops a locker off the end of the queue. Note that no storage gets cleared.
    function pop(IPoolManager.LockData storage self) internal {
        unchecked {
            self.length--;
        }
    }

    function getLock(uint256 i) internal view returns (address locker) {
        unchecked {
            uint256 position = OFFSET + i; // not in assembly because OFFSET is in the library scope
            /// @solidity memory-safe-assembly
            assembly {
                locker := sload(position)
            }
        }
    }

    function getActiveLock(IPoolManager.LockData storage self) internal view returns (address locker) {
        return getLock(self.length - 1);
    }
}
