// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {LockSentinel} from "../types/LockSentinel.sol";

/// @dev This library manages a custom storage implementation for a queue
///      that tracks current lockers. The "sentinel" storage slot for this data structure,
///      always passed in as IPoolManager.LockData storage self, stores not just the current
///      length of the queue but also the global count of non-zero deltas across all lockers.
///      The values of the data structure start at LOCK_DATA, and each value is a locker address.
library LockDataLibrary {
    using LockDataLibrary for LockSentinel;

    uint256 private constant SENTINEL = uint256(keccak256("Sentinel"));
    uint256 private constant LOCK_DATA = uint256(keccak256("LockData"));

    /// @dev Pushes a locker onto the end of the queue, and updates the sentinel storage slot.
    function push(LockSentinel sentinel, address locker) internal {
        // read current value from the sentinel storage slot
        uint128 _length = sentinel.length();
        unchecked {
            uint256 indexToWrite = LOCK_DATA + _length; // not in assembly because LOCK_DATA is in the library scope

            /// @solidity memory-safe-assembly
            assembly {
                // in the next storage slot, write the locker
                sstore(indexToWrite, locker)
            }
            sentinel.update(_length + 1, sentinel.nonzeroDeltaCount());
        }
    }

    /// @dev Pops a locker off the end of the queue. Note that no storage gets cleared.
    function pop(LockSentinel sentinel) internal {
        uint128 _length = sentinel.length();
        unchecked {
            sentinel.update(_length - 1, sentinel.nonzeroDeltaCount());
        }
    }

    function length(LockSentinel sentinel) internal pure returns (uint128 _length) {
        /// @solidity memory-safe-assembly
        assembly {
            _length := shr(128, sentinel)
        }
    }

    function nonzeroDeltaCount(LockSentinel sentinel) internal pure returns (uint128 _nonzeroDeltaCount) {
        /// @solidity memory-safe-assembly
        assembly {
            _nonzeroDeltaCount := sentinel
        }
    }

    function update(LockSentinel sentinel, uint128 _length, uint128 _nonzeroDeltaCount) internal {
        uint256 sentinelSlot = SENTINEL;
        assembly {
            sentinel :=
                or(
                    shl(128, _length),
                    and(0x00000000000000000000000000000000ffffffffffffffffffffffffffffffff, _nonzeroDeltaCount)
                )

            sstore(sentinelSlot, sentinel)
        }
    }

    function getLock(uint256 i) internal view returns (address locker) {
        unchecked {
            uint256 position = LOCK_DATA + i; // not in assembly because LOCK_DATA is in the library scope
            /// @solidity memory-safe-assembly
            assembly {
                locker := sload(position)
            }
        }
    }

    function getActiveLock(LockSentinel sentinel) internal view returns (address) {
        uint128 _length;
        unchecked {
            _length = sentinel.length() - 1;
        }
        return getLock(_length);
    }

    function getLockSentinel() internal view returns (LockSentinel sentinel) {
        uint256 sentinelSlot = SENTINEL;
        assembly {
            sentinel := sload(sentinelSlot)
        }
    }
}
