// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

/// @title Math functions that do not check inputs or outputs
/// @notice Contains methods that perform common math functions but do not do any overflow or underflow checks
library UnsafeMath {
    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            z := add(x, y)
        }
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            z := sub(x, y)
        }
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            z := mul(x, y)
        }
    }

    function div(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            z := div(x, y)
        }
    }

    /// @notice Returns ceil(x / y)
    /// @dev division by 0 has unspecified behavior, and must be checked externally
    /// @param x The dividend
    /// @param y The divisor
    /// @return z The quotient, ceil(x / y)
    function divRoundingUp(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            assembly {
                z := add(div(x, y), gt(mod(x, y), 0))
            }
        }
    }
}
