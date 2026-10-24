// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CurrencyDelta} from "../../src/libraries/CurrencyDelta.sol";
import {Currency} from "../../src/types/Currency.sol";

/// @notice Harness that exposes CurrencyDelta internal functions
contract CurrencyDeltaHarness {
    function getDelta(Currency currency, address target) external view returns (int256) {
        return CurrencyDelta.getDelta(currency, target);
    }

    function applyDelta(Currency currency, address target, int128 delta)
        external
        returns (int256 previous, int256 next)
    {
        return CurrencyDelta.applyDelta(currency, target, delta);
    }

    function computeSlot(address target, Currency currency) external pure returns (bytes32) {
        return CurrencyDelta._computeSlot(target, currency);
    }
}

contract CurrencyDeltaTest is Test {
    CurrencyDeltaHarness harness;

    Currency currency0;
    Currency currency1;
    address alice;
    address bob;

    function setUp() public {
        harness = new CurrencyDeltaHarness();
        currency0 = Currency.wrap(address(0x1111));
        currency1 = Currency.wrap(address(0x2222));
        alice = address(0xA11CE);
        bob = address(0xB0B);
    }

    function test_getDelta_defaultsToZero() public view {
        assertEq(harness.getDelta(currency0, alice), 0);
    }

    function test_applyDelta_positiveDelta() public {
        (int256 prev, int256 next) = harness.applyDelta(currency0, alice, 100);
        assertEq(prev, 0);
        assertEq(next, 100);
        assertEq(harness.getDelta(currency0, alice), 100);
    }

    function test_applyDelta_negativeDelta() public {
        (int256 prev, int256 next) = harness.applyDelta(currency0, alice, -50);
        assertEq(prev, 0);
        assertEq(next, -50);
        assertEq(harness.getDelta(currency0, alice), -50);
    }

    function test_applyDelta_accumulates() public {
        harness.applyDelta(currency0, alice, 100);
        (int256 prev, int256 next) = harness.applyDelta(currency0, alice, 200);
        assertEq(prev, 100);
        assertEq(next, 300);
    }

    function test_applyDelta_netToZero() public {
        harness.applyDelta(currency0, alice, 100);
        (int256 prev, int256 next) = harness.applyDelta(currency0, alice, -100);
        assertEq(prev, 100);
        assertEq(next, 0);
        assertEq(harness.getDelta(currency0, alice), 0);
    }

    function test_differentCurrencies_isolated() public {
        harness.applyDelta(currency0, alice, 100);
        harness.applyDelta(currency1, alice, -50);
        assertEq(harness.getDelta(currency0, alice), 100);
        assertEq(harness.getDelta(currency1, alice), -50);
    }

    function test_differentAddresses_isolated() public {
        harness.applyDelta(currency0, alice, 100);
        harness.applyDelta(currency0, bob, -200);
        assertEq(harness.getDelta(currency0, alice), 100);
        assertEq(harness.getDelta(currency0, bob), -200);
    }

    function test_computeSlot_deterministic() public view {
        bytes32 slot1 = harness.computeSlot(alice, currency0);
        bytes32 slot2 = harness.computeSlot(alice, currency0);
        assertEq(slot1, slot2);
    }

    function test_computeSlot_uniquePerPair() public view {
        bytes32 slot1 = harness.computeSlot(alice, currency0);
        bytes32 slot2 = harness.computeSlot(alice, currency1);
        bytes32 slot3 = harness.computeSlot(bob, currency0);
        assertTrue(slot1 != slot2);
        assertTrue(slot1 != slot3);
        assertTrue(slot2 != slot3);
    }

    function test_computeSlot_matchesExpected() public view {
        bytes32 expected = keccak256(abi.encode(uint256(uint160(alice)), uint256(uint160(Currency.unwrap(currency0)))));
        bytes32 actual = harness.computeSlot(alice, currency0);
        assertEq(actual, expected);
    }

    function test_fuzz_applyDelta(int128 delta1, int128 delta2) public {
        // Avoid overflow: ensure delta1 + delta2 doesn't overflow int256
        int256 sum = int256(delta1) + int256(delta2);

        (int256 prev1, int256 next1) = harness.applyDelta(currency0, alice, delta1);
        assertEq(prev1, 0);
        assertEq(next1, int256(delta1));

        (int256 prev2, int256 next2) = harness.applyDelta(currency0, alice, delta2);
        assertEq(prev2, int256(delta1));
        assertEq(next2, sum);
    }

    function test_applyDelta_maxInt128() public {
        int128 maxVal = type(int128).max;
        (int256 prev, int256 next) = harness.applyDelta(currency0, alice, maxVal);
        assertEq(prev, 0);
        assertEq(next, int256(maxVal));
    }

    function test_applyDelta_minInt128() public {
        int128 minVal = type(int128).min;
        (int256 prev, int256 next) = harness.applyDelta(currency0, alice, minVal);
        assertEq(prev, 0);
        assertEq(next, int256(minVal));
    }
}
