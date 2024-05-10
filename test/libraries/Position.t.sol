// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Position} from "../../src/libraries/Position.sol";

contract PositionTest is Test {
    using Position for mapping(bytes32 => Position.Info);

    mapping(bytes32 => Position.Info) internal positions;

    function test_fuzz_get(address owner, int24 tickLower, int24 tickUpper, bytes32 salt) public view {
        bytes32 positionKey = keccak256(abi.encodePacked(owner, tickLower, tickUpper, salt));
        Position.Info storage expectedPosition = positions[positionKey];
        Position.Info storage position = positions.get(owner, tickLower, tickUpper, salt);
        bytes32 expectedPositionSlot;
        bytes32 positionSlot;
        assembly ("memory-safe") {
            expectedPositionSlot := expectedPosition.slot
            positionSlot := position.slot
        }
        assertEq(positionSlot, expectedPositionSlot, "slots not equal");
    }
}
