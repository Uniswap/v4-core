// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

library ProtocolFeeLibrary {
    // Max protocol fee is 25% (2500 bips)
    uint16 public constant MAX_PROTOCOL_FEE = 2500;

    // Total bips
    uint16 internal constant BIPS_DENOMINATOR = 10_000;

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
            // The fee is represented in bips so it cannot be GREATER than the MAX_PROTOCOL_FEE.
            if ((fee0 > MAX_PROTOCOL_FEE) || (fee1 > MAX_PROTOCOL_FEE)) {
                return false;
            }
        }
        return true;
    }
}
