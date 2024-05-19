// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

import {IExtsload} from "./interfaces/IExtsload.sol";

/// @notice Enables public storage access for efficient state retrieval by external contracts.
/// https://eips.ethereum.org/EIPS/eip-2330#rationale
abstract contract Extsload is IExtsload {
    /// @inheritdoc IExtsload
    function extsload(bytes32 slot) external view returns (bytes32 value) {
        /// @solidity memory-safe-assembly
        assembly {
            value := sload(slot)
        }
    }

    /// @inheritdoc IExtsload
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

    /// @inheritdoc IExtsload
    function extsload(bytes32[] calldata slots) external view returns (bytes32[] memory) {
        // since the function is external and enters a new call context and exits right
        // after execution, Solidity's memory management convention can be disregarded
        // and a direct slice of memory can be returned
        /// @solidity memory-safe-assembly
        assembly {
            // The abi offset of dynamic array in the returndata is 32.
            mstore(0, 0x20)
            mstore(0x20, slots.length)
            // A left bit-shift of 5 is equivalent to multiplying by 32 but costs less gas.
            let end := add(0x40, shl(5, slots.length))
            // Return values will start at 64 while calldata offset is 68.
            for { let memptr := 0x40 } 1 {} {
                // Compute calldata offset using the memory offset and store loaded value.
                mstore(memptr, sload(calldataload(add(memptr, 0x04))))
                memptr := add(memptr, 0x20)
                if iszero(lt(memptr, end)) { break }
            }
            // The end offset is also the length of the returndata.
            return(0, end)
        }
    }
}
