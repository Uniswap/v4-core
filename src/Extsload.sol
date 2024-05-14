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

    /// @dev since the function is external and enters a new call context and exits right after execution, Solidity's memory management convention can be disregarded and a direct slice of memory can be returned
    function extsload(bytes32[] calldata slots) external view returns (bytes32[] memory) {
        assembly ("memory-safe") {
            // abi offset for dynamic array
            mstore(0, 0x20)
            mstore(0x20, slots.length)
            let end := add(0x40, shl(5, slots.length))
            let memptr := 0x40
            let calldataptr := slots.offset
            for {} 1 {} {
                mstore(memptr, sload(calldataload(calldataptr)))
                memptr := add(memptr, 0x20)
                calldataptr := add(calldataptr, 0x20)
                if iszero(lt(memptr, end)) { break }
            }
            return(0, end)
        }
    }
}
