// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/// @title NonzeroDeltaCount
/// @notice Tracks the count of non-zero currency deltas using transient storage
/// @dev This is a temporary library that allows us to use transient storage (tstore/tload)
/// for tracking the number of currencies with non-zero deltas during an unlock callback.
/// The count is used to ensure all deltas are settled before the unlock completes.
/// TODO: This library can be deleted when the `transient` keyword is fully supported and stabilized in Solidity.
/// Currently, assembly is used to access the `tstore` and `tload` opcodes directly for gas efficiency and availability.
/// @custom:security Transient storage is automatically cleared at the end of each transaction.
library NonzeroDeltaCount {
    /// @notice The transient storage slot for the nonzero delta count
    /// @dev Derived from: bytes32(uint256(keccak256("NonzeroDeltaCount")) - 1)
    /// Subtracting 1 ensures the slot doesn't collide with standard storage patterns
    bytes32 internal constant NONZERO_DELTA_COUNT_SLOT =
        0x7d4b3164c6e45b97e7d87b7125a44c5828d005af88f9d751cfd78729c5d99a0b;

    /// @notice Reads the current count of currencies with non-zero deltas
    /// @dev Uses tload opcode to read from transient storage
    /// @return count The current number of currencies with non-zero deltas
    function read() internal view returns (uint256 count) {
        assembly ("memory-safe") {
            // Load count from transient storage
            count := tload(NONZERO_DELTA_COUNT_SLOT)
        }
    }

    /// @notice Increments the count of currencies with non-zero deltas
    /// @dev Called when a currency's delta changes from zero to non-zero
    /// Uses tload/tstore opcodes for transient storage operations
    function increment() internal {
        assembly ("memory-safe") {
            // Load current count, add 1, store back
            let count := tload(NONZERO_DELTA_COUNT_SLOT)
            count := add(count, 1)
            tstore(NONZERO_DELTA_COUNT_SLOT, count)
        }
    }

    /// @notice Decrements the count of currencies with non-zero deltas
    /// @dev Called when a currency's delta changes from non-zero to zero.
    /// WARNING: Potential to underflow. Ensure checks are performed by integrating contracts.
    /// Current usage ensures this will not happen because we call decrement with known boundaries
    /// (only up to the number of times we call increment).
    function decrement() internal {
        assembly ("memory-safe") {
            // Load current count, subtract 1, store back
            // WARNING: No underflow check - caller must ensure count > 0
            let count := tload(NONZERO_DELTA_COUNT_SLOT)
            count := sub(count, 1)
            tstore(NONZERO_DELTA_COUNT_SLOT, count)
        }
    }
}
