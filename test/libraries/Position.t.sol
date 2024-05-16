// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Position} from "../../src/libraries/Position.sol";
import {SafeCast} from "../../src/libraries/SafeCast.sol";

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

    function test_fuzz_update(
        address owner,
        int24 tickLower,
        int24 tickUpper,
        bytes32 salt,
        int128 liquidityDelta,
        uint256 feeGrowthInside0X128,
        uint256 feeGrowthInside1X128,
        uint128 liquidity
    ) public {
        Position.Info storage position = positions.get(owner, tickLower, tickUpper, salt);
        position.liquidity = liquidity;
        position.feeGrowthInside0LastX128 = feeGrowthInside0X128;
        position.feeGrowthInside1LastX128 = feeGrowthInside1X128;
    
        if (position.liquidity == 0 && liquidityDelta == 0) {
            vm.expectRevert(Position.CannotUpdateEmptyPosition.selector);
        }
        uint128 oldLiquidity = position.liquidity;
        uint256 oldFeeGrowthInside0X128 = position.feeGrowthInside0LastX128;
        uint256 oldFeeGrowthInside1X128 = position.feeGrowthInside1LastX128;

        uint256 newLiquidity = uint256(int256(uint256(oldLiquidity)) + int256(liquidityDelta));
        if (newLiquidity > type(uint128).max) {
            vm.expectRevert(SafeCast.SafeCastOverflow.selector);
        }

        Position.update(position, liquidityDelta, feeGrowthInside0X128, feeGrowthInside1X128);
        if (liquidityDelta == 0) {
            assertEq(position.liquidity, oldLiquidity);
        } else {
            assertNotEq(position.liquidity, oldLiquidity);
        }

        assertEq(position.feeGrowthInside0LastX128, oldFeeGrowthInside0X128);
        assertEq(position.feeGrowthInside1LastX128, oldFeeGrowthInside1X128);
    }
}
