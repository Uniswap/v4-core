// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CurrencyReserves} from "../../src/libraries/CurrencyReserves.sol";
import {Currency} from "../../src/types/Currency.sol";

/// @notice Harness that exposes CurrencyReserves internal functions
contract CurrencyReservesHarness {
    function getSyncedCurrency() external view returns (Currency) {
        return CurrencyReserves.getSyncedCurrency();
    }

    function resetCurrency() external {
        CurrencyReserves.resetCurrency();
    }

    function syncCurrencyAndReserves(Currency currency, uint256 value) external {
        CurrencyReserves.syncCurrencyAndReserves(currency, value);
    }

    function getSyncedReserves() external view returns (uint256) {
        return CurrencyReserves.getSyncedReserves();
    }
}

contract CurrencyReservesTest is Test {
    CurrencyReservesHarness harness;

    function setUp() public {
        harness = new CurrencyReservesHarness();
    }

    function test_initialCurrencyIsZero() public view {
        Currency currency = harness.getSyncedCurrency();
        assertTrue(Currency.unwrap(currency) == address(0));
    }

    function test_initialReservesAreZero() public view {
        assertEq(harness.getSyncedReserves(), 0);
    }

    function test_syncCurrencyAndReserves() public {
        Currency currency = Currency.wrap(address(0xBEEF));
        uint256 reserves = 1000 ether;

        harness.syncCurrencyAndReserves(currency, reserves);

        assertEq(Currency.unwrap(harness.getSyncedCurrency()), address(0xBEEF));
        assertEq(harness.getSyncedReserves(), reserves);
    }

    function test_resetCurrency_clearsOnlyCurrency() public {
        Currency currency = Currency.wrap(address(0xBEEF));
        harness.syncCurrencyAndReserves(currency, 500);

        harness.resetCurrency();

        assertTrue(Currency.unwrap(harness.getSyncedCurrency()) == address(0));
        // Reserves remain after reset (only currency is cleared)
        assertEq(harness.getSyncedReserves(), 500);
    }

    function test_syncOverwritesPrevious() public {
        harness.syncCurrencyAndReserves(Currency.wrap(address(0x1)), 100);
        harness.syncCurrencyAndReserves(Currency.wrap(address(0x2)), 200);

        assertEq(Currency.unwrap(harness.getSyncedCurrency()), address(0x2));
        assertEq(harness.getSyncedReserves(), 200);
    }

    function test_fuzz_syncCurrencyAndReserves(address currencyAddr, uint256 reserves) public {
        Currency currency = Currency.wrap(currencyAddr);
        harness.syncCurrencyAndReserves(currency, reserves);

        assertEq(Currency.unwrap(harness.getSyncedCurrency()), currencyAddr);
        assertEq(harness.getSyncedReserves(), reserves);
    }

    function test_syncWithZeroReserves() public {
        Currency currency = Currency.wrap(address(0xCAFE));
        harness.syncCurrencyAndReserves(currency, 0);

        assertEq(Currency.unwrap(harness.getSyncedCurrency()), address(0xCAFE));
        assertEq(harness.getSyncedReserves(), 0);
    }

    function test_syncWithMaxReserves() public {
        Currency currency = Currency.wrap(address(0xDEAD));
        harness.syncCurrencyAndReserves(currency, type(uint256).max);

        assertEq(Currency.unwrap(harness.getSyncedCurrency()), address(0xDEAD));
        assertEq(harness.getSyncedReserves(), type(uint256).max);
    }

    function test_slotsAreCorrect() public pure {
        // Verify the slot constants match their documented derivation
        assertEq(
            CurrencyReserves.RESERVES_OF_SLOT,
            bytes32(uint256(keccak256("ReservesOf")) - 1)
        );
        assertEq(
            CurrencyReserves.CURRENCY_SLOT,
            bytes32(uint256(keccak256("Currency")) - 1)
        );
    }
}
