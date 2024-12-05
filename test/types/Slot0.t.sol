// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Slot0, Slot0Library} from "../../src/types/Slot0.sol";

contract TestSlot0 is Test {
    function test_slot0_constants_masks() public pure {
        // verify that the inline masks match the expected maximum values for their types
        assertEq(uint160(~uint256(0) >> (256 - 160)), type(uint160).max);
        assertEq(uint24(~uint256(0) >> (256 - 24)), type(uint24).max);
    }

    function test_fuzz_slot0_pack_unpack(uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee)
        public
        pure
    {
        // pack starting from the "lowest" field
        Slot0 _slot0 = Slot0.wrap(bytes32(0))
            .setSqrtPriceX96(sqrtPriceX96)
            .setTick(tick)
            .setProtocolFee(protocolFee)
            .setLpFee(lpFee);

        // verify each field was correctly packed and can be unpacked
        assertEq(_slot0.sqrtPriceX96(), sqrtPriceX96);
        assertEq(_slot0.tick(), tick);
        assertEq(_slot0.protocolFee(), protocolFee);
        assertEq(_slot0.lpFee(), lpFee);

        // pack starting from the "highest" field
        _slot0 = Slot0.wrap(bytes32(0))
            .setLpFee(lpFee)
            .setProtocolFee(protocolFee)
            .setTick(tick)
            .setSqrtPriceX96(sqrtPriceX96);

        // verify each field was correctly packed and can be unpacked
        assertEq(_slot0.sqrtPriceX96(), sqrtPriceX96);
        assertEq(_slot0.tick(), tick);
        assertEq(_slot0.protocolFee(), protocolFee);
        assertEq(_slot0.lpFee(), lpFee);
    }
}
