// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

import {Currency, CurrencyLibrary} from "./types/Currency.sol";
import {IProtocolFeeController} from "./interfaces/IProtocolFeeController.sol";
import {IHookFeeManager} from "./interfaces/IHookFeeManager.sol";
import {IFees} from "./interfaces/IFees.sol";
import {FeeLibrary} from "./libraries/FeeLibrary.sol";
import {Pool} from "./libraries/Pool.sol";
import {PoolKey} from "./types/PoolKey.sol";
import {Owned} from "./Owned.sol";

abstract contract Fees is IFees, Owned {
    using FeeLibrary for uint24;
    using CurrencyLibrary for Currency;

    uint8 public constant MIN_PROTOCOL_FEE_DENOMINATOR = 4;

    mapping(Currency currency => uint256) public protocolFeesAccrued;

    mapping(address hookAddress => mapping(Currency currency => uint256)) public hookFeesAccrued;

    IProtocolFeeController public protocolFeeController;

    uint256 private immutable controllerGasLimit;

    constructor(uint256 _controllerGasLimit) {
        controllerGasLimit = _controllerGasLimit;
    }

    function _fetchProtocolFees(PoolKey memory key)
        internal
        view
        returns (uint8 protocolSwapFee, uint8 protocolWithdrawFee)
    {
        if (address(protocolFeeController) != address(0)) {
            // note that EIP-150 mandates that calls requesting more than 63/64ths of remaining gas
            // will be allotted no more than this amount, so controllerGasLimit must be set with this
            // in mind.
            if (gasleft() < controllerGasLimit) revert ProtocolFeeCannotBeFetched();
            try protocolFeeController.protocolFeesForPool{gas: controllerGasLimit}(key) returns (
                uint8 updatedProtocolSwapFee, uint8 updatedProtocolWithdrawFee
            ) {
                protocolSwapFee = updatedProtocolSwapFee;
                protocolWithdrawFee = updatedProtocolWithdrawFee;
            } catch {}

            _checkProtocolFee(protocolSwapFee);
            _checkProtocolFee(protocolWithdrawFee);
        }
    }

    /// @notice There is no cap on the hook fee, but it is specified as a percentage taken on the amount after the protocol fee is applied, if there is a protocol fee.
    function _fetchHookFees(PoolKey memory key) internal view returns (uint8 hookSwapFee, uint8 hookWithdrawFee) {
        if (key.fee.hasHookSwapFee()) {
            hookSwapFee = IHookFeeManager(address(key.hooks)).getHookSwapFee(key);
        }

        if (key.fee.hasHookWithdrawFee()) {
            hookWithdrawFee = IHookFeeManager(address(key.hooks)).getHookWithdrawFee(key);
        }
    }

    function _checkProtocolFee(uint8 fee) internal pure {
        if (fee != 0) {
            uint8 fee0 = fee % 16;
            uint8 fee1 = fee >> 4;
            // The fee is specified as a denominator so it cannot be LESS than the MIN_PROTOCOL_FEE_DENOMINATOR (unless it is 0).
            if (
                (fee0 != 0 && fee0 < MIN_PROTOCOL_FEE_DENOMINATOR) || (fee1 != 0 && fee1 < MIN_PROTOCOL_FEE_DENOMINATOR)
            ) {
                revert FeeTooLarge();
            }
        }
    }

    function setProtocolFeeController(IProtocolFeeController controller) external onlyOwner {
        protocolFeeController = controller;
        emit ProtocolFeeControllerUpdated(address(controller));
    }

    function collectProtocolFees(address recipient, Currency currency, uint256 amount)
        external
        returns (uint256 amountCollected)
    {
        if (msg.sender != owner && msg.sender != address(protocolFeeController)) revert InvalidCaller();

        amountCollected = (amount == 0) ? protocolFeesAccrued[currency] : amount;
        protocolFeesAccrued[currency] -= amountCollected;
        currency.transfer(recipient, amountCollected);
    }

    function collectHookFees(address recipient, Currency currency, uint256 amount)
        external
        returns (uint256 amountCollected)
    {
        address hookAddress = msg.sender;

        amountCollected = (amount == 0) ? hookFeesAccrued[hookAddress][currency] : amount;
        recipient = (recipient == address(0)) ? hookAddress : recipient;

        hookFeesAccrued[hookAddress][currency] -= amountCollected;
        currency.transfer(recipient, amountCollected);
    }
}
