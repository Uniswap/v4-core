// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import "./UnsafeMath.sol";

library ProtocolFeeLibrary {
    // Max protocol fee is 0.1% (1000 pips)
    uint16 public constant MAX_PROTOCOL_FEE = 1000;

    // the protocol fee is represented in hundredths of a bip
    uint24 internal constant PIPS_DENOMINATOR = 1_000_000;

    function getZeroForOneFee(uint24 self) internal pure returns (uint16) {
        return uint16(self & (4096 - 1));
    }

    function getOneForZeroFee(uint24 self) internal pure returns (uint16) {
        return uint16(self >> 12);
    }

    function validate(uint24 self) internal pure returns (bool) {
        if (self != 0) {
            uint16 fee0 = getZeroForOneFee(self);
            uint16 fee1 = getOneForZeroFee(self);
            // The fee is represented in pips and it cannot be greater than the MAX_PROTOCOL_FEE.
            if ((fee0 > MAX_PROTOCOL_FEE) || (fee1 > MAX_PROTOCOL_FEE)) {
                return false;
            }
        }
        return true;
    }

    // Effective fee can never exceed 100% (1e6 pips)
    function calculateEffectiveFee(uint24 self, uint24 swapFee) internal pure returns (uint24) {
        unchecked {
            uint256 numerator = uint256(self) * uint256(swapFee);
            uint256 divider = PIPS_DENOMINATOR;
            return uint24(uint256(self) + swapFee - UnsafeMath.divRoundingUp(numerator, divider));
        }
    }
}
