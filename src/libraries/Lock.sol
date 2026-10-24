// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/// @title Lock
/// @notice Manages the unlock state of the PoolManager using transient storage
/// @dev This is a temporary library that allows us to use transient storage (tstore/tload)
/// for managing the lock state of the PoolManager during callback execution.
/// The unlock state ensures that pool actions can only be performed within a valid callback context.
/// TODO: This library can be deleted when the `transient` keyword is fully supported and stabilized in Solidity.
/// Currently, assembly is used to access the `tstore` and `tload` opcodes directly for gas efficiency and availability.
/// @custom:security Transient storage is automatically cleared at the end of each transaction,
/// ensuring the PoolManager is locked by default at the start of each transaction.
library Lock {
    /// @notice The transient storage slot for the unlock state
    /// @dev Derived from: bytes32(uint256(keccak256("Unlocked")) - 1)
    /// Subtracting 1 ensures the slot doesn't collide with standard storage patterns
    bytes32 internal constant IS_UNLOCKED_SLOT = 0xc090fc4683624cfc3884e9d8de5eca132f2d0ec062aff75d43c0465d5ceeab23;

    /// @notice Sets the PoolManager state to unlocked
    /// @dev Called at the beginning of the unlock callback to enable pool operations.
    /// Uses tstore opcode to write to transient storage.
    function unlock() internal {
        assembly ("memory-safe") {
            // Set unlock state to true (1) in transient storage
            tstore(IS_UNLOCKED_SLOT, true)
        }
    }

    /// @notice Sets the PoolManager state to locked
    /// @dev Called at the end of the unlock callback to disable pool operations.
    /// This ensures the PoolManager is properly secured after callback completion.
    function lock() internal {
        assembly ("memory-safe") {
            // Set unlock state to false (0) in transient storage
            tstore(IS_UNLOCKED_SLOT, false)
        }
    }

    /// @notice Checks if the PoolManager is currently unlocked
    /// @dev Used to verify that pool operations are being called within a valid callback context.
    /// Returns false by default (when transient storage hasn't been written to).
    /// @return unlocked True if the PoolManager is unlocked, false otherwise
    function isUnlocked() internal view returns (bool unlocked) {
        assembly ("memory-safe") {
            // Load unlock state from transient storage
            unlocked := tload(IS_UNLOCKED_SLOT)
        }
    }
}
