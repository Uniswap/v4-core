// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {IPoolManager} from "../interfaces/IPoolManager.sol";

library LockDataLibrary {
    uint256 private constant OFFSET = uint256(keccak256("LockData"));

    function push(IPoolManager.LockData storage self, address locker) internal {
        uint96 length = self.length;
        uint96 index = self.index;
        unchecked {
            uint256 indexToWrite = OFFSET + length;
            /// @solidity memory-safe-assembly
            assembly {
                let valueToWrite :=
                    or(
                        shl(96, locker),
                        // TODO might not be necessary to clean the upper bits of parentLockIndex?
                        and(0x0000000000000000000000000000000000000000ffffffffffffffffffffffff, index)
                    )
                sstore(indexToWrite, valueToWrite)
            }
            self.length = length + 1;
            self.index = length;
        }
    }

    function getLock(uint256 i) internal view returns (address locker, uint96 parentLockIndex) {
        unchecked {
            uint256 position = OFFSET + i;
            /// @solidity memory-safe-assembly
            assembly {
                let value := sload(position)
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
