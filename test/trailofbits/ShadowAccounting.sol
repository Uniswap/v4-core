// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IPoolManager} from "src/interfaces/IPoolManager.sol";

import {CurrencyLibrary, Currency} from "src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "src/types/PoolId.sol";
import {PoolKey} from "src/types/PoolKey.sol";

import {StateLibrary} from "src/libraries/StateLibrary.sol";
import {TransientStateLibrary} from "src/libraries/TransientStateLibrary.sol";

import {Deployers} from "test/utils/Deployers.sol";

import {PropertiesAsserts} from "test/trailofbits/PropertiesHelper.sol";

/// @notice This contract provides a way for the harness to perform "shadow accounting", a technique where
/// the harness maintains its own copy of the system's balances, deltas, and remittances. Gas-optimized
/// protocols like v4 often need to perform indirect accounting to save gas, but this opens the possibility
/// of an error in that indirect accounting that can be exploited, such as an LPer for one pool being able to
/// withdraw more tokens than should exist in that pool.
/// By maintaining our own, direct copy of the accounting, we can compare it to the results of v4's indirect
/// accounting to verify the indirect accounting's correctness.
contract ShadowAccounting is PropertiesAsserts, Deployers {
    using TransientStateLibrary for IPoolManager;

    struct PoolBalance {
        // While it makes more sense for these to be uint256, it drastically increases the complexity of the casting/math.
        // Fix it in the future.
        int256 amount0;
        int256 amount1;
    }

    // Tracks the tokens available in each pool for trading.
    mapping(PoolId => PoolBalance) PoolLiquidities;

    // Tracks the currency deltas for each actor.
    mapping(address => mapping(Currency => int256)) CurrencyDeltas;

    // Tracks the liquidity available for swapping within the entire system.
    mapping(Currency => uint256) SingletonLiquidity;

    // Tracks the amount of LP fees available for LPers to withdraw for each currency
    mapping(Currency => uint256) SingletonLPFees;

    // Our own counter for outstanding deltas, based on CurrencyDeltas.
    int256 OutstandingDeltas;

    // Used to track remittances for settle() properties.
    Currency RemittanceCurrency = CurrencyLibrary.ADDRESS_ZERO;
    // Any code that transfers currency between the actor and the pool manager should update this.
    int256 RemittanceAmount;

    // This should only be called when we expect transient storage to be cleared, ex: after a transaction terminates.
    function _clearTransientRemittances() internal {
        RemittanceCurrency = CurrencyLibrary.ADDRESS_ZERO;
        RemittanceAmount = 0;
    }

    function _addToActorsDebts(address actor, Currency currency, uint256 amount) internal {
        // UNI-ACTION-4
        assertLte(
            amount,
            uint256(type(int256).max),
            "Shadow Accounting: An actor's debited delta must not exceed int256.max for any single action."
        );
        _updateCurrencyDelta(actor, currency, -int256(amount));
    }

    function _addToActorsCredits(address actor, Currency currency, uint256 amount) internal {
        // UNI-ACTION-5
        assertLte(
            amount,
            uint256(type(int256).max),
            "Shadow Accounting: An actor's credited delta must not exceed int256.max for any single action."
        );
        _updateCurrencyDelta(actor, currency, int256(amount));
    }

    function _updateCurrencyDelta(address actor, Currency currency, int256 delta) internal {
        int256 prev = CurrencyDeltas[actor][currency];
        int256 newD = prev + delta;

        CurrencyDeltas[actor][currency] = newD;
        emit LogAddress("Shadow Accounting: Updating delta for actor", actor);
        emit LogAddress("Shadow Accounting: Updating currency being modified", address(Currency.unwrap(currency)));

        if (prev == 0 && newD != 0) {
            // add to array
            emit LogAddress(
                "Shadow Accounting: Adding currency to actor's deltas: ", address(Currency.unwrap(currency))
            );
            OutstandingDeltas += 1;
        } else if (prev != 0 && newD == 0) {
            emit LogString("Shadow Accounting: Removing currency from actor's deltas");
            OutstandingDeltas -= 1;
        }
        emit LogInt256("Shadow Accounting: New delta: ", newD);
        emit LogInt256("Shadow Accounting: Prev delta: ", prev);
        _sanityCheckCurrencyDelta(actor, currency);
    }

    function _sanityCheckCurrencyDelta(address actor, Currency currency) private {
        int256 uniswapCurrencyDelta = manager.currencyDelta(actor, currency);
        int256 harnessCurrencyDelta = CurrencyDeltas[actor][currency];
        assertEq(
            uniswapCurrencyDelta,
            harnessCurrencyDelta,
            "BUG: Harness currency delta does not match uniswap currency delta"
        );
    }
}
