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

    function extsload(bytes32[] calldata slots) external view returns (bytes32[] memory) {
        /// @solidity memory-safe-assembly
        assembly {
            let free := mload(64)
            // The offset of our array in the returndata is 32.
            mstore(free, 32)
            mstore(add(free, 32), slots.length)
            // Return values will start at `free + 64`. We compute the difference between the memory
            // and calldata offset so we don't have to track and update a separate memory offset.
            let relativeOffset := sub(add(free, 64), slots.offset)
            // A left bit-shift of 5 is equivalent to multiplying by 32 but costs less gas.
            let len := shl(5, slots.length)
            let srcEndOffset := add(slots.offset, len)
            // Iterate through the calldata array.
            for { let srcOffset := slots.offset } lt(srcOffset, srcEndOffset) { srcOffset := add(srcOffset, 32) } {
                // Compute memory offset using the computed relative offset and store loaded value.
                mstore(add(srcOffset, relativeOffset), sload(calldataload(srcOffset)))
            }
            // Directly returning avoids Solidity doing it which would trigger a re-encode, almost
            // doubling the total cost of the method.
            return(free, add(len, 0x40))
        }
    }
}
