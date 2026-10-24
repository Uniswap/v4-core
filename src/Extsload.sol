// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IExtsload} from "./interfaces/IExtsload.sol";

/**
 * @title Extsload
 * @notice Implements EIP-2330 by providing low-level, gas-optimized functions 
 * to read storage slots from an external contract. This is crucial for 
 * meta-transactions, gas-relay, and efficient off-chain state fetching.
 */
abstract contract Extsload is IExtsload {
    // Maximum number of slots allowed to be read in a single call to prevent DoS attacks.
    uint256 private constant MAX_SLOTS = 1000;

    /// @inheritdoc IExtsload
    function extsload(bytes32 slot) external view returns (bytes32) {
        // Read a single slot using the SLOAD opcode.
        assembly ("memory-safe") {
            // Load the value from the storage slot 'slot' into memory address 0.
            mstore(0, sload(slot))
            // Return the data starting from memory address 0, with length 32 bytes (0x20).
            return(0, 0x20)
        }
    }

    /// @inheritdoc IExtsload
    function extsload(bytes32 startSlot, uint256 nSlots) external view returns (bytes32[] memory) {
        require(nSlots <= MAX_SLOTS, "Extsload: Too many slots requested");
        
        assembly ("memory-safe") {
            // Get the current free memory pointer (0x40).
            let memptr := mload(0x40)
            let start := memptr
            
            // Calculate total data size in bytes (nSlots * 32).
            // shl(5, nSlots) is equivalent to nSlots * 32 (optimized gas cost).
            let length := shl(5, nSlots) 
            
            // ABI ENCODING START: Dynamic array requires an offset and length.
            
            // 1. Store the offset to the dynamic array data (32 bytes / 0x20).
            // This is the first element of the return data (memptr + 0).
            mstore(memptr, 0x20)
            
            // 2. Store the array length (number of slots).
            // This is the first word of the array data (memptr + 0x20).
            mstore(add(memptr, 0x20), nSlots)
            
            // Update memptr to the start of the first actual result slot (memptr + 0x40).
            mptr := add(memptr, 0x40)
            
            // Calculate the end address for the loop termination.
            let end := add(mptr, length)

            // --- LOOP TO READ CONSECUTIVE SLOTS ---
            for {} 1 {} {
                // Read the storage slot value and store it in the current memory pointer (mptr).
                mstore(mptr, sload(startSlot))
                
                // Advance memory pointer by 32 bytes (0x20).
                mptr := add(mptr, 0x20)
                
                // Advance storage slot index by 1.
                startSlot := add(startSlot, 1)
                
                // Break if the memory pointer reaches or exceeds the calculated end.
                if iszero(lt(mptr, end)) { break }
            }
            
            // Return the encoded data (offset + length + data)
            return(start, sub(end, start))
        }
    }

    /// @inheritdoc IExtsload
    function extsload(bytes32[] calldata slots) external view returns (bytes32[] memory) {
        // NOTE: The compiler automatically checks for calldata array length limit.
        assembly ("memory-safe") {
            let memptr := mload(0x40)
            let start := memptr
            
            // 1. Store the offset to the dynamic array data (0x20).
            mstore(memptr, 0x20)
            
            // 2. Store the array length (number of slots to read).
            let nSlots := calldataload(slots.offset) // The length is stored at the beginning of the calldata array data
            mstore(add(memptr, 0x20), nSlots)
            
            // Update memptr to the start of the first actual result slot.
            mptr := add(memptr, 0x40)
            
            // Calculate the end address based on length (nSlots * 32 bytes).
            let end := add(mptr, shl(5, nSlots))
            
            // Calldata offset to the array data entries (slots.offset + 0x20)
            // calldataload(slots.offset) is the length, so the data starts 0x20 after that.
            let calldataptr := add(slots.offset, 0x20) 
            
            // --- LOOP TO READ NON-CONSECUTIVE SLOTS ---
            for {} 1 {} {
                // Load the next slot address from calldata.
                let slotToLoad := calldataload(calldataptr)
                
                // Load the storage value from the calculated slot and store it in memory.
                mstore(mptr, sload(slotToLoad))
                
                // Advance memory pointer by 32 bytes (0x20).
                mptr := add(mptr, 0x20)
                
                // Advance calldata pointer by 32 bytes to the next slot address.
                calldataptr := add(calldataptr, 0x20)
                
                // Break if the memory pointer reaches or exceeds the calculated end.
                if iszero(lt(mptr, end)) { break }
            }
            
            // Return the encoded data.
            return(start, sub(end, start))
        }
    }
}
