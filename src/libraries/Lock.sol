// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

contract Lock {
    bool internal transient IS_UNLOCKED_SLOT;

    function unlock() internal {
        IS_UNLOCKED_SLOT = true;
    }

    function lock() internal {
        IS_UNLOCKED_SLOT = false;
    }

    function isUnlocked() internal view returns (bool unlocked) {
        unlocked = IS_UNLOCKED_SLOT;
    }
}
