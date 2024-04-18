// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

import {IExtsload} from "./interfaces/IExtsload.sol";

/// @notice Enables public storage access for efficient state retrieval by external contracts.
/// https://eips.ethereum.org/EIPS/eip-2330#rationale
abstract contract Extsload is IExtsload {
    function extsload(bytes32 slot) external view returns (bytes32 value) {
        /// @solidity memory-safe-assembly
        assembly {
            value := sload(slot)
        }
    }

    function extsload(bytes32 startSlot, uint256 nSlots) external view returns (bytes memory) {
        bytes memory value = new bytes(32 * nSlots);

        /// @solidity memory-safe-assembly
        assembly {
            for { let i := 0 } lt(i, nSlots) { i := add(i, 1) } {
                mstore(add(value, mul(add(i, 1), 32)), sload(add(startSlot, i)))
            }
        }

        return value;
    }
}
