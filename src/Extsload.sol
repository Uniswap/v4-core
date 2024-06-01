// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

import {IExtsload} from "./interfaces/IExtsload.sol";

/// @notice Enables public storage access for efficient state retrieval by external contracts.
/// https://eips.ethereum.org/EIPS/eip-2330#rationale
abstract contract Extsload is IExtsload {
    /// @inheritdoc IExtsload
    function extsload(bytes32 slot) external view returns (bytes32) {
        assembly ("memory-safe") {
            mstore(0, sload(slot))
            return(0, 0x20)
        }
    }

    /// @inheritdoc IExtsload
    function extsload(bytes32 startSlot, uint256 nSlots) external view returns (bytes memory) {
        assembly ("memory-safe") {
            // The abi offset of dynamic array in the returndata is 32.
            mstore(0, 0x20)
            // A left bit-shift of 5 is equivalent to multiplying by 32 but costs less gas.
            mstore(0x20, shl(5, nSlots))
            let end := add(0x40, shl(5, nSlots))
            for { let memptr := 0x40 } 1 {} {
                mstore(memptr, sload(startSlot))
                memptr := add(memptr, 0x20)
                startSlot := add(startSlot, 1)
                if iszero(lt(memptr, end)) { break }
            }
            // The end offset is also the length of the returndata.
            return(0, end)
        }
    }

    /// @inheritdoc IExtsload
    function extsload(bytes32[] calldata slots) external view returns (bytes32[] memory) {
        // since the function is external and enters a new call context and exits right
        // after execution, Solidity's memory management convention can be disregarded
        // and a direct slice of memory can be returned
        assembly ("memory-safe") {
            // Copy the abi offset of dynamic array and the length of the array to memory.
            calldatacopy(0, 0x04, 0x40)
            // A left bit-shift of 5 is equivalent to multiplying by 32 but costs less gas.
            let end := add(0x40, shl(5, slots.length))
            let calldataptr := slots.offset
            // Return values will start at 64 while calldata offset is 68.
            for { let memptr := 0x40 } 1 {} {
                mstore(memptr, sload(calldataload(calldataptr)))
                memptr := add(memptr, 0x20)
                calldataptr := add(calldataptr, 0x20)
                if iszero(lt(memptr, end)) { break }
            }
            // The end offset is also the length of the returndata.
            return(0, end)
        }
    }
}
