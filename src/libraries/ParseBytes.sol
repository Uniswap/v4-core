// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title ParseBytes
/// @notice Parses bytes returned from hooks and the byte selector used to check return selectors from hooks
/// @dev This library provides efficient parsing utilities for hook return values.
/// Hooks in Uniswap v4 return packed data that needs to be efficiently unpacked.
/// The return formats are:
/// - bytes4 only: Just the selector for validation
/// - (bytes4, int256): Selector and a 32-byte delta value
/// - (bytes4, int256, uint24): Selector, delta, and LP fee
/// All parsing uses assembly for gas efficiency since these are called frequently.
library ParseBytes {
    /// @notice Extracts the selector (first 4 bytes) from hook return data
    /// @dev Used to validate that hooks return the expected selector.
    /// Also used to parse the expected selector for comparison.
    /// @param result The bytes data returned from a hook call
    /// @return selector The first 4 bytes of the result, representing the function selector
    function parseSelector(bytes memory result) internal pure returns (bytes4 selector) {
        // equivalent: (selector,) = abi.decode(result, (bytes4, int256));
        assembly ("memory-safe") {
            // Load 32 bytes starting at position 0x20 (after the length prefix)
            // Only the first 4 bytes contain the selector, rest is padding
            selector := mload(add(result, 0x20))
        }
    }

    /// @notice Extracts the LP fee from hook return data
    /// @dev Used to get the dynamic LP fee returned by beforeSwap hooks.
    /// The fee is located at the third 32-byte slot in the return data.
    /// @param result The bytes data returned from a hook call (must be at least 96 bytes)
    /// @return lpFee The LP fee in hundredths of a bip (e.g., 3000 = 0.30%)
    function parseFee(bytes memory result) internal pure returns (uint24 lpFee) {
        // equivalent: (,, lpFee) = abi.decode(result, (bytes4, int256, uint24));
        assembly ("memory-safe") {
            // Load from position 0x60 (0x20 length + 0x20 selector + 0x20 delta)
            // The uint24 is right-aligned in the 32-byte slot
            lpFee := mload(add(result, 0x60))
        }
    }

    /// @notice Extracts the return delta from hook return data
    /// @dev Used to get the hook's delta modification from beforeSwap/afterSwap hooks.
    /// The delta represents how much the hook wants to modify the swap amounts.
    /// @param result The bytes data returned from a hook call (must be at least 64 bytes)
    /// @return hookReturn The int256 delta value returned by the hook
    function parseReturnDelta(bytes memory result) internal pure returns (int256 hookReturn) {
        // equivalent: (, hookReturnDelta) = abi.decode(result, (bytes4, int256));
        assembly ("memory-safe") {
            // Load from position 0x40 (0x20 length + 0x20 selector slot)
            // The full 32 bytes represent the int256 value
            hookReturn := mload(add(result, 0x40))
        }
    }
}
