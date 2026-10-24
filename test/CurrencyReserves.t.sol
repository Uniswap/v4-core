// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// Import the library under test, the standard test utilities, and the custom type
import {CurrencyReserves} from "../src/libraries/CurrencyReserves.sol";
import {Test} from "forge-std/Test.sol";
import {Currency} from "../src/types/Currency.sol";

// This test contract verifies the functionality of the CurrencyReserves library,
// particularly its storage slot mechanism for synchronizing currency and reserve values.
contract CurrencyReservesTest is Test {
    // Enable library functions to be called directly on the Currency type
    using CurrencyReserves for Currency;

    Currency currency0;

    /**
     * @dev Sets up a wrapper for a sample address (0xbeef) to represent a currency.
     */
    function setUp() public {
        currency0 = Currency.wrap(address(0xbeef));
    }

    /**
     * @dev Tests basic synchronization: setting values once and verifying retrieval.
     */
    function test_getReserves_returns_set() public {
        currency0.syncCurrencyAndReserves(100);
        uint256 value = CurrencyReserves.getSyncedReserves();
        
        // Assert the stored reserve value is correct
        assertEq(value, 100);
        
        // Assert the stored currency address is correct (unwrapped for comparison)
        assertEq(Currency.unwrap(CurrencyReserves.getSyncedCurrency()), Currency.unwrap(currency0));
    }

    /**
     * @dev Tests overwriting synchronized values, verifying the latest set value is returned.
     */
    function test_set_twice_returns_correct_value() public {
        currency0.syncCurrencyAndReserves(100);
        currency0.syncCurrencyAndReserves(200);
        uint256 value = CurrencyReserves.getSyncedReserves();

        assertEq(value, 200);
        assertEq(Currency.unwrap(CurrencyReserves.getSyncedCurrency()), Currency.unwrap(currency0));
    }

    /**
     * @dev Tests the specific reset function, which should clear the currency address 
     * but leave the reserve value intact (as per library design).
     */
    function test_reset_currency() public {
        currency0.syncCurrencyAndReserves(100);
        
        // Initial state check
        assertEq(CurrencyReserves.getSyncedReserves(), 100);
        assertEq(Currency.unwrap(CurrencyReserves.getSyncedCurrency()), Currency.unwrap(currency0));
        
        CurrencyReserves.resetCurrency();
        
        // Post-reset check: Reserves should remain 100
        assertEq(CurrencyReserves.getSyncedReserves(), 100);
        
        // Post-reset check: Currency address should be reset to address(0)
        assertEq(Currency.unwrap(CurrencyReserves.getSyncedCurrency()), address(0));
    }

    /**
     * @dev Verifies the deterministic storage slot calculation for the reserves.
     * This uses the common collision-resistant 'keccak256(slot_name) - 1' pattern.
     */
    function test_reservesOfSlot() public pure {
        assertEq(bytes32(uint256(keccak256("ReservesOf")) - 1), CurrencyReserves.RESERVES_OF_SLOT);
    }

    /**
     * @dev Verifies the deterministic storage slot calculation for the currency address.
     */
    function test_syncSlot() public pure {
        assertEq(bytes32(uint256(keccak256("Currency")) - 1), CurrencyReserves.CURRENCY_SLOT);
    }

    /**
     * @dev Fuzz test to ensure that the get/set logic works for arbitrary currency addresses and values.
     * @param currency An arbitrary currency address wrapper (provided by the fuzzer).
     * @param value An arbitrary uint256 value (provided by the fuzzer).
     */
    function test_fuzz_get_set(Currency currency, uint256 value) public {
        // Skip max uint256, although Solidity 0.8+ handles overflow, this is often done 
        // to avoid testing specific edge cases related to max value math operations.
        vm.assume(value != type(uint256).max);
        
        currency.syncCurrencyAndReserves(value);

        // Verify that the retrieved currency matches the set currency
        assertEq(Currency.unwrap(CurrencyReserves.getSyncedCurrency()), Currency.unwrap(currency));
        
        // Verify that the retrieved reserve value matches the set value
        assertEq(CurrencyReserves.getSyncedReserves(), value);
    }
}
