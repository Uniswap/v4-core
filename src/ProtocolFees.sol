// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Currency} from "./types/Currency.sol";
import {IProtocolFeeController} from "./interfaces/IProtocolFeeController.sol";
import {IProtocolFees} from "./interfaces/IProtocolFees.sol";
import {PoolKey} from "./types/PoolKey.sol";
import {ProtocolFeeLibrary} from "./libraries/ProtocolFeeLibrary.sol";
import {Owned} from "solmate/src/auth/Owned.sol";
import {PoolId, PoolIdLibrary} from "./types/PoolId.sol";
import {Pool} from "./libraries/Pool.sol";
import {CustomRevert} from "./libraries/CustomRevert.sol";

/// @notice Contract handling the setting and accrual of protocol fees
abstract contract ProtocolFees is IProtocolFees, Owned {
    using ProtocolFeeLibrary for uint24;
    using PoolIdLibrary for PoolKey;
    using Pool for Pool.State;
    using CustomRevert for bytes4;

    /// @inheritdoc IProtocolFees
    mapping(Currency currency => uint256 amount) public protocolFeesAccrued;

    /// @inheritdoc IProtocolFees
    IProtocolFeeController public protocolFeeController;

    uint256 private immutable controllerGasLimit;

    constructor(uint256 _controllerGasLimit) Owned(msg.sender) {
        controllerGasLimit = _controllerGasLimit;
    }

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

        amountCollected = (amount == 0) ? protocolFeesAccrued[currency] : amount;
        protocolFeesAccrued[currency] -= amountCollected;
        currency.transfer(recipient, amountCollected);
    }

    /// @dev abstract internal function to allow the ProtocolFees contract to access pool state
    /// @dev this is overriden in PoolManager.sol to give access to the _pools mapping
    function _getPool(PoolId id) internal virtual returns (Pool.State storage);

    /// @notice Fetch the protocol fees for a given pool, returning false if the call fails or the returned fees are invalid.
    /// @dev to prevent an invalid protocol fee controller from blocking pools from being initialized
    ///      the success of this function is NOT checked on initialize and if the call fails, the protocol fees are set to 0.
    /// @dev the success of this function must be checked when called in setProtocolFee
    function _fetchProtocolFee(PoolKey memory key) internal returns (bool success, uint24 protocolFee) {
        if (address(protocolFeeController) != address(0)) {
            // note that EIP-150 mandates that calls requesting more than 63/64ths of remaining gas
            // will be allotted no more than this amount, so controllerGasLimit must be set with this
            // in mind.
            if (gasleft() < controllerGasLimit) ProtocolFeeCannotBeFetched.selector.revertWith();

            uint256 gasLimit = controllerGasLimit;
            address toAddress = address(protocolFeeController);

            bytes memory data = abi.encodeCall(IProtocolFeeController.protocolFeeForPool, (key));
            uint256 returnData;
            assembly ("memory-safe") {
                success := call(gasLimit, toAddress, 0, add(data, 0x20), mload(data), 0, 0)

                // success if return data size is 32 bytes
                // only load the return value if it is 32 bytes to prevent gas griefing
                success := and(success, eq(returndatasize(), 32))

                // load the return data if success is true
                if success {
                    let fmp := mload(0x40)
                    returndatacopy(fmp, 0, returndatasize())
                    returnData := mload(fmp)
                    mstore(fmp, 0)
                }
            }

            // Ensure return data does not overflow a uint24 and that the underlying fees are within bounds.
            (success, protocolFee) = success && (returnData == uint24(returnData))
                && uint24(returnData).isValidProtocolFee() ? (true, uint24(returnData)) : (false, 0);
        }
    }

    function _updateProtocolFees(Currency currency, uint256 amount) internal {
        unchecked {
            protocolFeesAccrued[currency] += amount;
        }
    }
}
