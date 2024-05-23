// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

library CustomRevert {
    /// @dev Reverts with the selector of a custom error in the scratch space
    function revertWith(bytes4 selector) internal pure {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0, selector)
            revert(0, 0x04)
        }
    }
}
