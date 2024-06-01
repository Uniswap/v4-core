// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import {IExttload} from "./interfaces/IExttload.sol";

/// @notice Enables public transient storage access for efficient state retrieval by external contracts.
/// https://eips.ethereum.org/EIPS/eip-2330#rationale
abstract contract Exttload is IExttload {
    /// @inheritdoc IExttload
    function exttload(bytes32 slot) external view returns (bytes32) {
        assembly ("memory-safe") {
            mstore(0, tload(slot))
            return(0, 0x20)
        }
    }

    /// @inheritdoc IExttload
    function exttload(bytes32[] calldata slots) external view returns (bytes32[] memory) {
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
                mstore(memptr, tload(calldataload(calldataptr)))
                memptr := add(memptr, 0x20)
                calldataptr := add(calldataptr, 0x20)
                if iszero(lt(memptr, end)) { break }
            }
            // The end offset is also the length of the returndata.
            return(0, end)
        }
    }
}
