// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Extsload} from "../src/Extsload.sol";

contract Loadable is Extsload {}

/// @author philogy <https://github.com/philogy>
contract ExtsloadTest is Test {
    Loadable loadable = new Loadable();

    function test_load10_sparse() public {
        bytes32[] memory keys = new bytes32[](10);
        for (uint256 i = 0; i < keys.length; i++) {
            keys[i] = keccak256(abi.encode(i));
            vm.store(address(loadable), keys[i], bytes32(i));
        }

        bytes32[] memory values = loadable.extsload(keys);
        vm.snapshotGasLastCall("sparse external sload");
        assertEq(values.length, keys.length);
        for (uint256 i = 0; i < values.length; i++) {
            assertEq(values[i], bytes32(i));
        }
    }

    function test_fuzz_consecutiveExtsload(uint256 startSlot, uint256 length, uint256 seed) public {
        length = bound(length, 0, 1000);
        startSlot = bound(startSlot, 0, type(uint256).max - length);
        for (uint256 i; i < length; ++i) {
            vm.store(address(loadable), bytes32(startSlot + i), keccak256(abi.encode(i, seed)));
        }
        bytes32[] memory values = loadable.extsload(bytes32(startSlot), length);
        assertEq(values.length, length);
        for (uint256 i; i < length; ++i) {
            assertEq(values[i], keccak256(abi.encode(i, seed)));
        }
    }

    function test_fuzz_extsload(uint256 length, uint256 seed, bytes memory dirtyBits) public {
        length = bound(length, 0, 1000);
        bytes32[] memory slots = new bytes32[](length);
        bytes32[] memory expected = new bytes32[](length);
        for (uint256 i; i < length; ++i) {
            slots[i] = keccak256(abi.encode(i, seed));
            expected[i] = keccak256(abi.encode(slots[i]));
            vm.store(address(loadable), slots[i], expected[i]);
        }
        bytes32[] memory values = loadable.extsload(slots);
        assertEq(values, expected);
        // test with dirty bits
        bytes memory data = abi.encodeWithSignature("extsload(bytes32[])", (slots));
        bytes memory malformedData = bytes.concat(data, dirtyBits);
        (bool success, bytes memory returnData) = address(loadable).staticcall(malformedData);
        assertTrue(success, "extsload failed");
        assertEq(returnData.length % 0x20, 0, "return data length is not a multiple of 32");
        assertEq(abi.decode(returnData, (bytes32[])), expected);
    }
}
