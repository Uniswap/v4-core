// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Currency} from "./types/Currency.sol";
import {CurrencyReserves} from "./libraries/CurrencyReserves.sol";
import {IProtocolFees} from "./interfaces/IProtocolFees.sol";
import {PoolKey} from "./types/PoolKey.sol";
import {ProtocolFeeLibrary} from "./libraries/ProtocolFeeLibrary.sol";
import {Owned} from "solmate/src/auth/Owned.sol";
import {PoolId} from "./types/PoolId.sol";
import {Pool} from "./libraries/Pool.sol";
import {CustomRevert} from "./libraries/CustomRevert.sol";

/// @notice Contract handling the setting and accrual of protocol fees
abstract contract ProtocolFees is IProtocolFees, Owned {
    using ProtocolFeeLibrary for uint24;
    using Pool for Pool.State;
    using CustomRevert for bytes4;

    /// @inheritdoc IProtocolFees
    mapping(Currency currency => uint256 amount) public protocolFeesAccrued;

    /// @inheritdoc IProtocolFees
    address public protocolFeeController;

    constructor(address initialOwner) Owned(initialOwner) {}

    /// @inheritdoc IProtocolFees
    function setProtocolFeeController(address controller) external onlyOwner {
        protocolFeeController = controller;
        emit ProtocolFeeControllerUpdated(controller);
    }

    /// @inheritdoc IProtocolFees
    function setProtocolFee(PoolKey memory key, uint24 newProtocolFee) external {
        if (msg.sender != protocolFeeController) InvalidCaller.selector.revertWith();
        if (!newProtocolFee.isValidProtocolFee()) ProtocolFeeTooLarge.selector.revertWith(newProtocolFee);
        PoolId id = key.toId();
        _getPool(id).setProtocolFee(newProtocolFee);
        emit ProtocolFeeUpdated(id, newProtocolFee);
    }

    /// @inheritdoc IProtocolFees
    function collectProtocolFees(address recipient, Currency currency, uint256 amount)
        external
        returns (uint256 amountCollected)
    {
        if (msg.sender != protocolFeeController) InvalidCaller.selector.revertWith();
        if (!currency.isAddressZero() && CurrencyReserves.getSyncedCurrency() == currency) {
            // prevent transfer between the sync and settle balanceOfs (native settle uses msg.value)
            ProtocolFeeCurrencySynced.selector.revertWith();
        }

        amountCollected = (amount == 0) ? protocolFeesAccrued[currency] : amount;
        protocolFeesAccrued[currency] -= amountCollected;
        currency.transfer(recipient, amountCollected);
    }

    /// @dev abstract internal function to allow the ProtocolFees contract to access the lock
    function _isUnlocked() internal virtual returns (bool);

    /// @dev abstract internal function to allow the ProtocolFees contract to access pool state
    /// @dev this is overridden in PoolManager.sol to give access to the _pools mapping
    function _getPool(PoolId id) internal virtual returns (Pool.State storage);

    function _updateProtocolFees(Currency currency, uint256 amount) internal {
        unchecked {
            protocolFeesAccrued[currency] += amount;
        }
    }
}
