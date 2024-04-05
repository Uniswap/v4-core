// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Reserves} from "../src/libraries/Reserves.sol";
import {Test} from "forge-std/Test.sol";
import {Currency} from "../src/types/Currency.sol";

contract ReservesTest is Test {
    using Reserves for Currency;

    Currency currency0;

    function setUp() public {
        currency0 = Currency.wrap(address(0xbeef));
    }

    function test_get_succeeds_default() public {
        uint256 value = currency0.getReserves();
        assertEq(value, 0);
    }

    function test_get_returns_set() public {
        currency0.setReserves(100);
        uint256 value = currency0.getReserves();
        assertEq(value, 100);
    }

    function test_set_twice_returns_correct_value() public {
        currency0.setReserves(100);
        currency0.setReserves(200);
        uint256 value = currency0.getReserves();
        assertEq(value, 200);
    }

    function test_reservesOfSlot() public {
        assertEq(uint256(keccak256("ReservesOf")) - 1, Reserves.RESERVES_OF_SLOT);
    }

    function test_fuzz_get_set(Currency currency, uint256 value) public {
        currency.setReserves(value);
        assertEq(currency.getReserves(), value);
    }
}
