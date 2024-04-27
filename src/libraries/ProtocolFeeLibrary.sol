// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import "./UnsafeMath.sol";

library ProtocolFeeLibrary {
    // Max protocol fee is 0.1% (1000 pips)
    uint16 public constant MAX_PROTOCOL_FEE = 1000;

    uint24 public constant FEE_0_THRESHOLD = 1001;
    uint24 public constant FEE_1_THRESHOLD = 1001 << 12;

    // the protocol fee is represented in hundredths of a bip
    uint256 internal constant PIPS_DENOMINATOR = 1_000_000;

    function getZeroForOneFee(uint24 self) internal pure returns (uint16) {
        return uint16(self & 0xfff);
    }

    function getOneForZeroFee(uint24 self) internal pure returns (uint16) {
        return uint16(self >> 12);
    }

    /// @dev The fee is represented in pips and it cannot be greater than the MAX_PROTOCOL_FEE.
    function validate(uint24 self) internal pure returns (bool success) {
        // Equivalent to: self == 0 ? true : (getZeroForOneFee(self) <= MAX_PROTOCOL_FEE && getOneForZeroFee(self) <= MAX_PROTOCOL_FEE)
        assembly {
            let isZeroForOneFeeOk := slt(sub(and(self, 0xfff), FEE_0_THRESHOLD), 0)
            let isOneForZeroFeeOk := slt(sub(self, FEE_1_THRESHOLD), 0)
            success := or(iszero(self), and(isZeroForOneFeeOk, isOneForZeroFeeOk))
        }
    }

    // The protocol fee is taken from the input amount first and then the LP fee is taken from the remaining
    // The swap fee is capped at 100%
    // equivalent to protocolFee + lpFee(1_000_000 - protocolFee) / 1_000_000
    function calculateSwapFee(uint24 self, uint24 lpFee) internal pure returns (uint24 swapFee) {
        assembly {
            let numerator := mul(self, lpFee)
            let divRoundingUp := add(div(numerator, PIPS_DENOMINATOR), gt(mod(numerator, PIPS_DENOMINATOR), 0))
            swapFee := sub(add(self, lpFee), divRoundingUp)
        }
    }
}
