// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/// @notice This is a temporary library that allows us to use transient storage (tstore/tload)
/// TODO: This library can be deleted when we have the transient keyword support in solidity.
library Lock {
    // The slot holding the unlocked state, transiently. bytes32(uint256(keccak256("Unlocked")) - 1)
    bytes32 internal constant IS_UNLOCKED_SLOT = 0xc090fc4683624cfc3884e9d8de5eca132f2d0ec062aff75d43c0465d5ceeab23;

    function unlock() internal {
        assembly ("memory-safe") {
            // unlock
            tstore(IS_UNLOCKED_SLOT, true)
        }
    }

    function lock() internal {
        assembly ("memory-safe") {
            tstore(IS_UNLOCKED_SLOT, false)
        }
    }

    function isUnlocked() internal view returns (bool unlocked) {
        assembly ("memory-safe") {
            unlocked := tload(IS_UNLOCKED_SLOT)
        }
    }
}
