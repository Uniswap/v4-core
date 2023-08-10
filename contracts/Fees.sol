// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

import {Currency, CurrencyLibrary} from "./types/Currency.sol";
import {IProtocolFeeController} from "./interfaces/IProtocolFeeController.sol";
import {IHookFeeManager} from "./interfaces/IHookFeeManager.sol";
import {FeeLibrary} from "./libraries/FeeLibrary.sol";
import {Pool} from "./libraries/Pool.sol";
import {PoolKey} from "./types/PoolKey.sol";
import {Owned} from "./Owned.sol";

library Fees {
    using FeeLibrary for uint24;
    using CurrencyLibrary for Currency;

    error InvalidCaller();
    error FeeTooLarge();
    error ProtocolFeeCannotBeFetched();

    event FeeManagerChanged(address indexed oldManager, address indexed newManager);
    event ProtocolFeeControllerUpdated(address protocolFeeController);

    struct FeeData {
        mapping(Currency currency => uint256) protocolFeesAccrued;
        mapping(address hookAddress => mapping(Currency currency => uint256)) hookFeesAccrued;
        IProtocolFeeController protocolFeeController;
        address feeManager;
    }

    uint8 public constant MIN_PROTOCOL_FEE_DENOMINATOR = 4;
    uint256 public constant DEFAULT_CONTROLLER_GAS_LIMIT = 500_000;

    function init(FeeData storage self) external {
        self.feeManager = msg.sender;
        emit FeeManagerChanged(address(0), msg.sender);
    }

    function setFeeManager(FeeData storage self, address _manager) external {
        if (msg.sender != self.feeManager) revert InvalidCaller();
        emit FeeManagerChanged(self.feeManager, _manager);
        self.feeManager = _manager;
    }

    function fetchProtocolFees(FeeData storage self, PoolKey memory key)
        external
        view
        returns (uint8 protocolSwapFee, uint8 protocolWithdrawFee)
    {
        if (address(self.protocolFeeController) != address(0)) {
            // note that EIP-150 mandates that calls requesting more than 63/64ths of remaining gas
            // will be allotted no more than this amount, so controllerGasLimit must be set with this
            // in mind.
            if (gasleft() < DEFAULT_CONTROLLER_GAS_LIMIT) revert ProtocolFeeCannotBeFetched();
            try self.protocolFeeController.protocolFeesForPool{gas: DEFAULT_CONTROLLER_GAS_LIMIT}(key) returns (
                uint8 updatedProtocolSwapFee, uint8 updatedProtocolWithdrawFee
            ) {
                protocolSwapFee = updatedProtocolSwapFee;
                protocolWithdrawFee = updatedProtocolWithdrawFee;
            } catch {}

            _checkProtocolFee(protocolSwapFee);
            _checkProtocolFee(protocolWithdrawFee);
        }
    }

    function fetchHookFees(PoolKey memory key) external view returns (uint8 hookSwapFee, uint8 hookWithdrawFee) {
        if (key.fee.hasHookSwapFee()) {
            hookSwapFee = IHookFeeManager(address(key.hooks)).getHookSwapFee(key);
        }

        if (key.fee.hasHookWithdrawFee()) {
            hookWithdrawFee = IHookFeeManager(address(key.hooks)).getHookWithdrawFee(key);
        }
    }

    function setProtocolFeeController(FeeData storage self, IProtocolFeeController controller) external {
        self.protocolFeeController = controller;
        emit ProtocolFeeControllerUpdated(address(controller));
    }

    function collectProtocolFees(FeeData storage self, address recipient, Currency currency, uint256 amount)
        external
        returns (uint256 amountCollected)
    {
        if (msg.sender != self.feeManager && msg.sender != address(self.protocolFeeController)) revert InvalidCaller();

        amountCollected = (amount == 0) ? self.protocolFeesAccrued[currency] : amount;
        self.protocolFeesAccrued[currency] -= amountCollected;
        currency.transfer(recipient, amountCollected);
    }

    function collectHookFees(FeeData storage self, address recipient, Currency currency, uint256 amount)
        external
        returns (uint256 amountCollected)
    {
        address hookAddress = msg.sender;

        amountCollected = (amount == 0) ? self.hookFeesAccrued[hookAddress][currency] : amount;
        recipient = (recipient == address(0)) ? hookAddress : recipient;

        self.hookFeesAccrued[hookAddress][currency] -= amountCollected;
        currency.transfer(recipient, amountCollected);
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
}
