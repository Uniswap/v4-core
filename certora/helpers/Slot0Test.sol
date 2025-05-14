// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Slot0, Slot0Library} from "src/types/Slot0.sol";

contract Slot0Test {
    using Slot0Library for Slot0;
    Slot0 testSlot;

    // #### GETTERS ####
    function sqrtPriceX96() external view returns (uint160) {
        return testSlot.sqrtPriceX96();
    }

    function tick() external view returns (int24) {
        return testSlot.tick();
    }

    function protocolFee() external view returns (uint24) {
        return testSlot.protocolFee();
    }

    function lpFee() external view returns (uint24) {
        return testSlot.lpFee();
    }

    // #### SETTERS ####
    function setSqrtPriceX96(uint160 _sqrtPriceX96) external {
        testSlot = testSlot.setSqrtPriceX96(_sqrtPriceX96);
    }

    function setTick(int24 _tick) external {
        testSlot = testSlot.setTick(_tick);
    }

    function setProtocolFee(uint24 _protocolFee) external {
        testSlot = testSlot.setProtocolFee(_protocolFee);
    }

    function setLpFee(uint24 _lpFee) external {
        testSlot = testSlot.setLpFee(_lpFee);
    }
}