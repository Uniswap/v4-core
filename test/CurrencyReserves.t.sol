// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {CurrencyReserves} from "../src/libraries/CurrencyReserves.sol";
import {Test} from "forge-std/Test.sol";
import {Currency} from "../src/types/Currency.sol";

contract CurrencyReservesTest is Test {
    using CurrencyReserves for Currency;

    Currency currency0;

    function setUp() public {
        currency0 = Currency.wrap(address(0xbeef));
    }

    function test_getReserves_returns_set() public {
        currency0.syncCurrencyAndReserves(100);
        uint256 value = CurrencyReserves.getSyncedReserves();
        assertEq(value, 100);
        assertEq(Currency.unwrap(CurrencyReserves.getSyncedCurrency()), Currency.unwrap(currency0));
    }

    function test_set_twice_returns_correct_value() public {
        currency0.syncCurrencyAndReserves(100);
        currency0.syncCurrencyAndReserves(200);
        uint256 value = CurrencyReserves.getSyncedReserves();
        assertEq(value, 200);
        assertEq(Currency.unwrap(CurrencyReserves.getSyncedCurrency()), Currency.unwrap(currency0));
    }

    function test_reset_currency() public {
        currency0.syncCurrencyAndReserves(100);
        uint256 value = CurrencyReserves.getSyncedReserves();
        assertEq(value, 100);
        assertEq(Currency.unwrap(CurrencyReserves.getSyncedCurrency()), Currency.unwrap(currency0));
        CurrencyReserves.resetCurrency();
        uint256 valueAfterReset = CurrencyReserves.getSyncedReserves();
        assertEq(valueAfterReset, 100);
        assertEq(Currency.unwrap(CurrencyReserves.getSyncedCurrency()), address(0));
    }

    function test_reservesOfSlot() public pure {
        assertEq(bytes32(uint256(keccak256("ReservesOf")) - 1), CurrencyReserves.RESERVES_OF_SLOT);
    }

    function test_syncSlot() public pure {
        assertEq(bytes32(uint256(keccak256("Currency")) - 1), CurrencyReserves.CURRENCY_SLOT);
    }

    function test_fuzz_get_set(Currency currency, uint256 value) public {
        vm.assume(value != type(uint256).max);
        currency.syncCurrencyAndReserves(value);

        assertEq(Currency.unwrap(CurrencyReserves.getSyncedCurrency()), Currency.unwrap(currency));
        assertEq(CurrencyReserves.getSyncedReserves(), value);
    }
}
