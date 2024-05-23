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

    /// @dev Reverts with a custom error with an address argument in the scratch space
    function revertWithAddress(bytes4 selector, address addr) internal pure {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0, selector)
            mstore(0x04, addr)
            revert(0, 0x24)
        }
    }

    /// @dev Reverts with a custom error with an int24 argument in the scratch space
    function revertWithInt24(bytes4 selector, int24 value) internal pure {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0, selector)
            mstore(0x04, value)
            revert(0, 0x24)
        }
    }

    /// @dev Reverts with a custom error with a uint160 argument in the scratch space
    function revertWithUint160(bytes4 selector, uint160 value) internal pure {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0, selector)
            mstore(0x04, value)
            revert(0, 0x24)
        }
    }
}
