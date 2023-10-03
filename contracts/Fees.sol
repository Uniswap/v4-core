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

    /// @dev You must call _isValidProtocolFees after calling this function.
    function _fetchProtocolFees(PoolKey memory key) internal returns (uint24 protocolFees) {
        uint16 protocolSwapFee;
        uint16 protocolWithdrawFee;
        if (address(protocolFeeController) != address(0)) {
            // note that EIP-150 mandates that calls requesting more than 63/64ths of remaining gas
            // will be allotted no more than this amount, so controllerGasLimit must be set with this
            // in mind.
            if (gasleft() < controllerGasLimit) revert ProtocolFeeCannotBeFetched();
            (bool _success, bytes memory data) = address(protocolFeeController).call{gas: controllerGasLimit}(
                abi.encodeWithSelector(IProtocolFeeController.protocolFeesForPool.selector, key)
            );
            if (data.length > 32) return 0;

            bytes32 _data;
            assembly {
                // get first word from return data
                _data := mload(add(data, 0x20))
            }
            // mask dirty bits from data, keeping 24 bits
            protocolFees = uint24(uint256(_data) & 0xFFFFFF);
            bool noDirtyBits = uint256(protocolFees) == uint256(_data);

            protocolSwapFee = uint16(protocolFees >> 12);
            protocolWithdrawFee = uint16(protocolFees & 0xFFF);

            if (!noDirtyBits || !_isValidProtocolFees(protocolFees)) {
                return 0;
            }
        }
    }

    /// @notice There is no cap on the hook fee, but it is specified as a percentage taken on the amount after the protocol fee is applied, if there is a protocol fee.
    function _fetchHookFees(PoolKey memory key) internal view returns (uint24 hookFees) {
        if (address(key.hooks) != address(0)) {
            try IHookFeeManager(address(key.hooks)).getHookFees(key) returns (uint24 hookFeesRaw) {
                uint24 swapFeeMask = key.fee.hasHookSwapFee() ? 0xFFF000 : 0;
                uint24 withdrawFeeMask = key.fee.hasHookWithdrawFee() ? 0xFFF : 0;
                uint24 fullFeeMask = swapFeeMask | withdrawFeeMask;
                hookFees = hookFeesRaw & fullFeeMask;
            } catch {}
        }
    }

    function _isValidProtocolFees(uint24 protocolFees) internal pure returns (bool) {
        if (protocolFees != 0) {
            uint16 protocolSwapFee = uint16(protocolFees >> 12);
            uint16 protocolWithdrawFee = uint16(protocolFees & 0xFFF);
            if (protocolSwapFee != 0) {
                uint16 fee0 = protocolSwapFee % 64;
                uint16 fee1 = protocolSwapFee >> 6;
                // The fee is specified as a denominator so it cannot be LESS than the MIN_PROTOCOL_FEE_DENOMINATOR (unless it is 0).
                if (
                    (fee0 != 0 && fee0 < MIN_PROTOCOL_FEE_DENOMINATOR)
                        || (fee1 != 0 && fee1 < MIN_PROTOCOL_FEE_DENOMINATOR)
                ) {
                    return false;
                }
            }
            if (protocolWithdrawFee != 0) {
                uint16 fee0 = protocolWithdrawFee % 64;
                uint16 fee1 = protocolWithdrawFee >> 6;
                // The fee is specified as a denominator so it cannot be LESS than the MIN_PROTOCOL_FEE_DENOMINATOR (unless it is 0).
                if (
                    (fee0 != 0 && fee0 < MIN_PROTOCOL_FEE_DENOMINATOR)
                        || (fee1 != 0 && fee1 < MIN_PROTOCOL_FEE_DENOMINATOR)
                ) {
                    return false;
                }
            }
        }
        return true;
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
