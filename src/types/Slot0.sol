// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Slot0
/// @author Uniswap Labs
/// @notice A packed representation of pool state variables stored in a single bytes32 slot
/// @dev Slot0 is a packed version of a solidity structure, optimized for gas efficiency
/// by storing multiple values in a single 32-byte storage slot.
///
/// Layout (256 bits total, from MSB to LSB):
/// | 24 bits empty | 24 bits lpFee | 12 bits protocolFee 1->0 | 12 bits protocolFee 0->1 | 24 bits tick | 160 bits sqrtPriceX96 |
///
/// Fields (from least significant bit):
/// - sqrtPriceX96 (160 bits): The current sqrt(price) as a Q64.96 value
/// - tick (24 bits, signed): The current tick, representing log base 1.0001 of price
/// - protocolFee (24 bits): Protocol fee in hundredths of a bip (max 1000 = 0.1%)
///   - Lower 12 bits: fee for 0->1 swaps
///   - Upper 12 bits: fee for 1->0 swaps
/// - lpFee (24 bits): The LP fee of the pool (does not include dynamic fee flag)
///
/// Fee order: protocolFee is taken from input first, then lpFee from remaining
type Slot0 is bytes32;

using Slot0Library for Slot0 global;

/// @title Slot0Library
/// @author Uniswap Labs
/// @notice Library for efficient bit manipulation of the packed Slot0 type
/// @dev Provides gas-optimized getters and setters using inline assembly.
/// All operations are pure and use memory-safe assembly patterns.
library Slot0Library {
    /// @dev Bitmask for extracting the 160-bit sqrtPriceX96 value (lowest 160 bits)
    uint160 internal constant MASK_160_BITS = 0x00FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    /// @dev Bitmask for extracting 24-bit values (tick, fees)
    uint24 internal constant MASK_24_BITS = 0xFFFFFF;

    /// @dev Bit offset for the tick field (starts after sqrtPriceX96's 160 bits)
    uint8 internal constant TICK_OFFSET = 160;

    /// @dev Bit offset for the protocol fee field (starts after tick's 24 bits)
    uint8 internal constant PROTOCOL_FEE_OFFSET = 184;

    /// @dev Bit offset for the LP fee field (starts after protocolFee's 24 bits)
    uint8 internal constant LP_FEE_OFFSET = 208;

    // ╔═══════════════════════════════════════════════════════════════════════╗
    // ║                              GETTERS                                   ║
    // ╚═══════════════════════════════════════════════════════════════════════╝

    /// @notice Extracts the sqrtPriceX96 value from the packed Slot0
    /// @dev sqrtPriceX96 occupies the lowest 160 bits of Slot0.
    /// Represents sqrt(price) * 2^96 in Q64.96 fixed-point format.
    /// @param _packed The packed Slot0 value to extract from
    /// @return _sqrtPriceX96 The current sqrt price as a Q64.96 value
    function sqrtPriceX96(Slot0 _packed) internal pure returns (uint160 _sqrtPriceX96) {
        /// @solidity memory-safe-assembly
        assembly ("memory-safe") {
            // Mask the lowest 160 bits to extract sqrtPriceX96
            _sqrtPriceX96 := and(MASK_160_BITS, _packed)
        }
    }

    /// @notice Extracts the tick value from the packed Slot0
    /// @dev tick occupies bits 160-183 (24 bits) of Slot0.
    /// Uses signextend to properly handle negative tick values.
    /// The tick represents the log base 1.0001 of the price.
    /// @param _packed The packed Slot0 value to extract from
    /// @return _tick The current tick (signed 24-bit integer)
    function tick(Slot0 _packed) internal pure returns (int24 _tick) {
        /// @solidity memory-safe-assembly
        assembly ("memory-safe") {
            // Shift right by TICK_OFFSET, then sign-extend from 3 bytes (24 bits)
            // signextend(2, x) sign-extends x from byte index 2 (3 bytes)
            _tick := signextend(2, shr(TICK_OFFSET, _packed))
        }
    }

    /// @notice Extracts the protocol fee value from the packed Slot0
    /// @dev protocolFee occupies bits 184-207 (24 bits) of Slot0.
    /// The fee is split: lower 12 bits for 0->1 direction, upper 12 bits for 1->0.
    /// Fee is in hundredths of a bip (1e-6), max 1000 = 0.1%.
    /// @param _packed The packed Slot0 value to extract from
    /// @return _protocolFee The combined protocol fee (both directions)
    function protocolFee(Slot0 _packed) internal pure returns (uint24 _protocolFee) {
        /// @solidity memory-safe-assembly
        assembly ("memory-safe") {
            // Shift right to position protocolFee at LSB, then mask 24 bits
            _protocolFee := and(MASK_24_BITS, shr(PROTOCOL_FEE_OFFSET, _packed))
        }
    }

    /// @notice Extracts the LP fee value from the packed Slot0
    /// @dev lpFee occupies bits 208-231 (24 bits) of Slot0.
    /// For dynamic fee pools, this value does NOT include the dynamic fee flag.
    /// Fee is in hundredths of a bip (1e-6), so 3000 = 0.30%.
    /// @param _packed The packed Slot0 value to extract from
    /// @return _lpFee The current LP fee of the pool
    function lpFee(Slot0 _packed) internal pure returns (uint24 _lpFee) {
        /// @solidity memory-safe-assembly
        assembly ("memory-safe") {
            // Shift right to position lpFee at LSB, then mask 24 bits
            _lpFee := and(MASK_24_BITS, shr(LP_FEE_OFFSET, _packed))
        }
    }

    // ╔═══════════════════════════════════════════════════════════════════════╗
    // ║                              SETTERS                                   ║
    // ╚═══════════════════════════════════════════════════════════════════════╝

    /// @notice Sets the sqrtPriceX96 value in the packed Slot0
    /// @dev Clears the lowest 160 bits and sets the new value.
    /// The new value is masked to ensure only 160 bits are used.
    /// @param _packed The original packed Slot0 value
    /// @param _sqrtPriceX96 The new sqrt price to set
    /// @return _result The new Slot0 with updated sqrtPriceX96
    function setSqrtPriceX96(Slot0 _packed, uint160 _sqrtPriceX96) internal pure returns (Slot0 _result) {
        /// @solidity memory-safe-assembly
        assembly ("memory-safe") {
            // Clear lowest 160 bits of _packed, then OR with masked _sqrtPriceX96
            _result := or(and(not(MASK_160_BITS), _packed), and(MASK_160_BITS, _sqrtPriceX96))
        }
    }

    /// @notice Sets the tick value in the packed Slot0
    /// @dev Clears bits 160-183 and sets the new tick value.
    /// The tick is masked to 24 bits before being shifted into position.
    /// @param _packed The original packed Slot0 value
    /// @param _tick The new tick value to set (will be truncated to 24 bits)
    /// @return _result The new Slot0 with updated tick
    function setTick(Slot0 _packed, int24 _tick) internal pure returns (Slot0 _result) {
        /// @solidity memory-safe-assembly
        assembly ("memory-safe") {
            // Create mask at tick position, clear those bits, then OR with new value
            _result := or(and(not(shl(TICK_OFFSET, MASK_24_BITS)), _packed), shl(TICK_OFFSET, and(MASK_24_BITS, _tick)))
        }
    }

    /// @notice Sets the protocol fee value in the packed Slot0
    /// @dev Clears bits 184-207 and sets the new protocol fee.
    /// Protocol fee format: lower 12 bits for 0->1, upper 12 bits for 1->0.
    /// @param _packed The original packed Slot0 value
    /// @param _protocolFee The new protocol fee to set (combined for both directions)
    /// @return _result The new Slot0 with updated protocol fee
    function setProtocolFee(Slot0 _packed, uint24 _protocolFee) internal pure returns (Slot0 _result) {
        /// @solidity memory-safe-assembly
        assembly ("memory-safe") {
            // Create mask at protocol fee position, clear those bits, then OR with new value
            _result :=
                or(
                    and(not(shl(PROTOCOL_FEE_OFFSET, MASK_24_BITS)), _packed),
                    shl(PROTOCOL_FEE_OFFSET, and(MASK_24_BITS, _protocolFee))
                )
        }
    }

    /// @notice Sets the LP fee value in the packed Slot0
    /// @dev Clears bits 208-231 and sets the new LP fee.
    /// For dynamic fee pools, this should not include the dynamic fee flag.
    /// @param _packed The original packed Slot0 value
    /// @param _lpFee The new LP fee to set
    /// @return _result The new Slot0 with updated LP fee
    function setLpFee(Slot0 _packed, uint24 _lpFee) internal pure returns (Slot0 _result) {
        /// @solidity memory-safe-assembly
        assembly ("memory-safe") {
            // Create mask at LP fee position, clear those bits, then OR with new value
            _result :=
                or(and(not(shl(LP_FEE_OFFSET, MASK_24_BITS)), _packed), shl(LP_FEE_OFFSET, and(MASK_24_BITS, _lpFee)))
        }
    }
}
