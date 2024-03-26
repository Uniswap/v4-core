// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {PoolKey} from "../types/PoolKey.sol";

library ProtocolFeeLibrary {
    using ProtocolFeeLibrary for uint24;

    function getZeroForOneFee(uint24 self) internal pure returns (uint16) {
        return uint16(self % 4096);
    }

    function getOneForZeroFee(uint24 self) internal pure returns (uint16) {
        return uint16(self >> 12);
    }
}
