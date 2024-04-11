// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Currency, CurrencyLibrary} from "../types/Currency.sol";
import {IERC20Minimal} from "../interfaces/external/IERC20Minimal.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";

library CurrencySettleTake {
    using CurrencyLibrary for Currency;

    /// @notice Settle (pay) a currency to the PoolManager
    /// @param currency Currency to settle
    /// @param manager IPoolManager to settle to
    /// @param payer Address of the payer, the token sender
    /// @param amount Amount to send
    /// @param burn If true, burn the ERC-6909 token, otherwise ERC20-transfer to the PoolManager
    function settle(Currency currency, IPoolManager manager, address payer, uint256 amount, bool burn) internal {
        // for native currencies or burns, calling sync is not required
        // short circuit for ERC-6909 burns to support ERC-6909-wrapped native tokens
        if (burn) {
            manager.burn(payer, currency.toId(), amount);
        } else if (currency.isNative()) {
            manager.settle{value: amount}(currency);
        } else {
            // TODO: call sync when transient reserves is merged
            IERC20Minimal(Currency.unwrap(currency)).transferFrom(payer, address(manager), amount);
            manager.settle(currency);
        }
    }

    /// @notice Take (receive) a currency from the PoolManager
    /// @param currency Currency to take
    /// @param manager IPoolManager to take from
    /// @param recipient Address of the recipient, the token receiver
    /// @param amount Amount to receive
    /// @param claims If true, mint the ERC-6909 token, otherwise ERC20-transfer from the PoolManager to recipient
    function take(Currency currency, IPoolManager manager, address recipient, uint256 amount, bool claims) internal {
        claims ? manager.mint(recipient, currency.toId(), amount) : manager.take(currency, recipient, amount);
    }
}
