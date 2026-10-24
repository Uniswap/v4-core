// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {LPFeeLibrary} from "../../src/libraries/LPFeeLibrary.sol";
import {ProtocolFeeLibrary} from "../../src/libraries/ProtocolFeeLibrary.sol";

contract ProtocolFeeLibraryTest {

    function MAX_PROTOCOL_FEE() public pure returns (uint24) {
        return uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE);
    }

    function MAX_LP_FEE() public pure returns (uint24) {
        return LPFeeLibrary.MAX_LP_FEE;
    }

    function getZeroForOneFee(uint24 fee) public pure returns (uint24) {
        return ProtocolFeeLibrary.getZeroForOneFee(fee);
    }

    function getOneForZeroFee(uint24 fee) public pure returns (uint24) {
        return ProtocolFeeLibrary.getOneForZeroFee(fee);
    }

    function isValidProtocolFee(uint24 fee) public pure returns (bool) {
        return ProtocolFeeLibrary.isValidProtocolFee(fee);
    }

    function calculateSwapFee(uint16 self, uint24 lpFee) public pure returns (uint24) {
        return ProtocolFeeLibrary.calculateSwapFee(self, lpFee);
    }
}
