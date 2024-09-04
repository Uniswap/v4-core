// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Currency} from "./types/Currency.sol";
import {IProtocolFeeController} from "./interfaces/IProtocolFeeController.sol";
import {IProtocolFees} from "./interfaces/IProtocolFees.sol";
import {PoolKey} from "./types/PoolKey.sol";
import {ProtocolFeeLibrary} from "./libraries/ProtocolFeeLibrary.sol";
import {BipsLibrary} from "./libraries/BipsLibrary.sol";
import {Owned} from "solmate/src/auth/Owned.sol";
import {PoolId} from "./types/PoolId.sol";
import {Pool} from "./libraries/Pool.sol";
import {CustomRevert} from "./libraries/CustomRevert.sol";

/// @notice Contract handling the setting and accrual of protocol fees
abstract contract ProtocolFees is IProtocolFees, Owned {
    using ProtocolFeeLibrary for uint24;
    using Pool for Pool.State;
    using CustomRevert for bytes4;
    using BipsLibrary for uint256;

    /// @inheritdoc IProtocolFees
    mapping(Currency currency => uint256 amount) public protocolFeesAccrued;

    /// @inheritdoc IProtocolFees
    IProtocolFeeController public protocolFeeController;

    // a percentage of the block.gaslimit denoted in basis points, used as the gas limit for fee controller calls
    // 100 bps is 1%, at 30M gas, the limit is 300K
    uint256 private constant BLOCK_LIMIT_BPS = 100;

    constructor() Owned(msg.sender) {}

    /// @inheritdoc IProtocolFees
    function setProtocolFeeController(IProtocolFeeController controller) external onlyOwner {
        protocolFeeController = controller;
        emit ProtocolFeeControllerUpdated(address(controller));
    }

    /// @inheritdoc IProtocolFees
    function setProtocolFee(PoolKey memory key, uint24 newProtocolFee) external {
        if (msg.sender != address(protocolFeeController)) InvalidCaller.selector.revertWith();
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
        if (msg.sender != address(protocolFeeController)) InvalidCaller.selector.revertWith();
        if (_isUnlocked()) ContractUnlocked.selector.revertWith();

        amountCollected = (amount == 0) ? protocolFeesAccrued[currency] : amount;
        protocolFeesAccrued[currency] -= amountCollected;
        currency.transfer(recipient, amountCollected);
    }

    /// @dev abstract internal function to allow the ProtocolFees contract to access the lock
    function _isUnlocked() internal virtual returns (bool);

    /// @dev abstract internal function to allow the ProtocolFees contract to access pool state
    /// @dev this is overridden in PoolManager.sol to give access to the _pools mapping
    function _getPool(PoolId id) internal virtual returns (Pool.State storage);

    /// @notice Fetch the protocol fees for a given pool
    /// @dev the success of this function is false if the call fails or the returned fees are invalid
    /// @dev to prevent an invalid protocol fee controller from blocking pools from being initialized
    /// the success of this function is NOT checked on initialize and if the call fails, the protocol fees are set to 0.
    function _fetchProtocolFee(PoolKey memory key) internal returns (uint24 protocolFee) {
        if (address(protocolFeeController) != address(0)) {
            uint256 controllerGasLimit = block.gaslimit.calculatePortion(BLOCK_LIMIT_BPS);

            // note that EIP-150 mandates that calls requesting more than 63/64ths of remaining gas
            // will be allotted no more than this amount, so controllerGasLimit must be set with this
            // in mind.
            if (gasleft() < controllerGasLimit) ProtocolFeeCannotBeFetched.selector.revertWith();

            address toAddress = address(protocolFeeController);

            bytes memory data = abi.encodeCall(IProtocolFeeController.protocolFeeForPool, (key));

            bool success;
            uint256 returnData;
            assembly ("memory-safe") {
                // only load the first 32 bytes of the return data to prevent gas griefing
                success := call(controllerGasLimit, toAddress, 0, add(data, 0x20), mload(data), 0, 32)
                // if success is false this wont actually be returned, instead 0 will be returned
                returnData := mload(0)

                // success if return data size is 32 bytes
                success := and(success, eq(returndatasize(), 32))
            }

            // Ensure return data does not overflow a uint24 and that the underlying fees are within bounds.
            protocolFee = success && (returnData == uint24(returnData)) && uint24(returnData).isValidProtocolFee()
                ? uint24(returnData)
                : 0;
        }
    }

    function _updateProtocolFees(Currency currency, uint256 amount) internal {
        unchecked {
            protocolFeesAccrued[currency] += amount;
        }
    }
}
