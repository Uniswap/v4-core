// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import "./UnsafeMath.sol";

library ProtocolFeeLibrary {
    // Max protocol fee is 0.1% (1000 pips)
    uint16 public constant MAX_PROTOCOL_FEE = 1000;

    // the protocol fee is represented in hundredths of a bip
    uint256 internal constant PIPS_DENOMINATOR = 1_000_000;

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

    // The protocol fee is taken from the input amount first and then the LP fee is taken from the remaining
    // The swap fee is capped at 100%
    // equivalent to protocolFee + lpFee(1_000_000 - protocolFee) / 1_000_000
    function calculateSwapFee(uint24 self, uint24 lpFee) internal pure returns (uint24) {
        unchecked {
            uint256 numerator = uint256(self) * uint256(lpFee);
            return uint24(uint256(self) + lpFee - UnsafeMath.divRoundingUp(numerator, PIPS_DENOMINATOR));
        }
    }
}
