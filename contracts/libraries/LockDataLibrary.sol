// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {IPoolManager} from "../interfaces/IPoolManager.sol";

import "forge-std/console2.sol";

/// @dev This library manages a custom storage implementation for a queue
///      that tracks current lockers. The "sentinel" storage slot for this data structure,
///      always passed in as IPoolManager.LockData storage self, stores not just the current
///      length of the queue but also the global count of non-zero deltas across all lockers.
///      The values of the data structure start at LOCK_DATA, and each value is a locker address.
library LockDataLibrary {
    uint256 private constant SENTINEL = uint256(keccak256("Sentinel"));
    uint256 private constant LOCK_DATA = uint256(keccak256("LockData"));

    /// @dev Pushes a locker onto the end of the queue, and updates the sentinel storage slot.
    function push(address locker) internal {
        // read current value from the sentinel storage slot
        IPoolManager.LockSentinel memory sentinel = getLockSentinel();

        unchecked {
            uint128 length = sentinel.length;
            uint256 indexToWrite = LOCK_DATA + length; // not in assembly because OFFSET is in the library scope

            // update the length at the sentinel
            sentinel.length = length + 1;
            uint256 sentinelSlot = SENTINEL;

            /// @solidity memory-safe-assembly
            assembly {
                // in the next storage slot, write the locker
                sstore(indexToWrite, locker)
                sstore(sentinelSlot, sentinel)
            }
        }
    }

    /// @dev Pops a locker off the end of the queue. Note that no storage gets cleared.
    function pop() internal {
        IPoolManager.LockSentinel memory sentinel = getLockSentinel();
        uint256 sentinelSlot = SENTINEL;
        unchecked {
            sentinel.length--;
        }
        assembly {
            // update the length at the sentinel
            sstore(sentinelSlot, sentinel)
        }
    }

    function getLock(uint256 i) internal view returns (address locker) {
        unchecked {
            uint256 position = LOCK_DATA + i; // not in assembly because OFFSET is in the library scope
            /// @solidity memory-safe-assembly
            assembly {
                locker := sload(position)
            }
        }
    }

    function getActiveLock() internal view returns (address) {
        IPoolManager.LockSentinel memory sentinel = getLockSentinel();

        return getLock(sentinel.length - 1);
    }

    function getLockSentinel() internal view returns (IPoolManager.LockSentinel memory sentinel) {
        uint256 sentinelSlot = SENTINEL;
        assembly {
            sentinel := sload(sentinelSlot)
        }
        console2.log("length inside library");
        console2.log(sentinel.length);
    }

    function increaseDeltaCount() internal {
        uint256 sentinelSlot = SENTINEL;
        IPoolManager.LockSentinel memory sentinel;

        assembly {
            sentinel := sload(sentinelSlot)
        }
        unchecked {
            sentinel.nonzeroDeltaCount++;
        }

        assembly {
            sstore(sentinelSlot, sentinel)
        }
    }

    function decreaseDeltaCount() internal {
        uint256 sentinelSlot = SENTINEL;
        IPoolManager.LockSentinel memory sentinel;

        assembly {
            sentinel := sload(sentinelSlot)
        }
        unchecked {
            sentinel.nonzeroDeltaCount--;
        }

        assembly {
            sstore(sentinelSlot, sentinel)
        }
    }
}
