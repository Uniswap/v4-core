// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Currency, CurrencyLibrary} from "../../src/types/Currency.sol";
import {IERC20Minimal} from "../../src/interfaces/external/IERC20Minimal.sol";
import {IPoolManager} from "../../src/interfaces/IPoolManager.sol";

/// @notice Library used to interact with PoolManager.sol to settle any open deltas.
/// To settle a positive delta (a credit to the user), a user may take or mint.
/// To settle a negative delta (a debt on the user), a user make transfer or burn to pay off a debt.
/// @dev `sync()` is called before any ERC-20 transfer in `settle`, and before any native
/// settle as well, in order to reset the synced-currency slot and avoid the DoS path
/// documented above `PoolManager._settle`.
library CurrencySettler {
    /// @notice Settle (pay) a currency to the PoolManager
    /// @dev For non-burn ERC-20 settles, `sync(currency)` is called so the manager can
    /// measure the post-transfer reserves delta. For native settles, `sync(address(0))`
    /// is called so the synced-currency slot is reset to the zero address; otherwise, if a
    /// non-zero currency was previously synced in the same unlock callback (by this library,
    /// by a hook, or by any nested action), `PoolManager._settle` would revert with
    /// `NonzeroNativeValue`. The burn branch skips `sync` because `PoolManager.burn` accounts
    /// the delta directly without consulting the synced-currency slot.
    /// @param currency Currency to settle
    /// @param manager IPoolManager to settle to
    /// @param payer Address of the payer, the token sender
    /// @param amount Amount to send
    /// @param burn If true, burn the ERC-6909 token, otherwise ERC20-transfer to the PoolManager
    function settle(Currency currency, IPoolManager manager, address payer, uint256 amount, bool burn) internal {
        // short circuit for ERC-6909 burns to support ERC-6909-wrapped native tokens
        if (burn) {
            manager.burn(payer, currency.toId(), amount);
        } else if (currency.isAddressZero()) {
            // Reset the synced-currency slot to address(0) so that `_settle` treats
            // `msg.value` as the payment. Without this, a previously-synced non-zero
            // currency in the same unlock callback would cause `_settle` to revert with
            // `NonzeroNativeValue` (see PoolManager.sol:_settle).
            manager.sync(CurrencyLibrary.ADDRESS_ZERO);
            manager.settle{value: amount}();
        } else {
            manager.sync(currency);
            if (payer != address(this)) {
                IERC20Minimal(Currency.unwrap(currency)).transferFrom(payer, address(manager), amount);
            } else {
                IERC20Minimal(Currency.unwrap(currency)).transfer(address(manager), amount);
            }
            manager.settle();
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
