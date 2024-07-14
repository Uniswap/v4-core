// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Currency} from "../types/Currency.sol";
import {IProtocolFeeController} from "../interfaces/IProtocolFeeController.sol";
import {PoolId} from "../types/PoolId.sol";
import {PoolKey} from "../types/PoolKey.sol";

interface IProtocolFees {
    /// @notice Thrown when not enough gas is provided to look up the protocol fee
    error ProtocolFeeCannotBeFetched();
    /// @notice Thrown when protocol fee is set too high
    error InvalidProtocolFee();

    /// @notice Thrown when collectProtocolFees or setProtocolFee is not called by the controller.
    error InvalidCaller();

    event ProtocolFeeControllerUpdated(address protocolFeeController);

    event ProtocolFeeUpdated(PoolId indexed id, uint24 protocolFee);

    /// @notice Given a currency address, returns the protocol fees accrued in that currency
    /// @param currency The currency to check
    /// @return amount The amount of protocol fees accrued in the currency
    function protocolFeesAccrued(Currency currency) external view returns (uint256);

    /// @notice Sets the protocol fee for the given pool
    /// @param key The key of the pool to set a protocol fee for
    /// @param fee The fee to set
    function setProtocolFee(PoolKey memory key, uint24 fee) external;

    /// @notice Sets the protocol fee controller
    /// @param protocolFeeController The new protocol fee controller
    function setProtocolFeeController(IProtocolFeeController protocolFeeController) external;

    /// @notice Collects the protocol fees for a given recipient and currency, returning the amount collected
    /// @param recipient The address to receive the protocol fees
    /// @param currency The currency to withdraw
    /// @param amount The amount of currency to withdraw
    /// @return uint256 The amount of currency successfully withdrawn
    function collectProtocolFees(address recipient, Currency currency, uint256 amount) external returns (uint256);

    /// @return protocolFeeController The currency protocol fee controller
    function protocolFeeController() external view returns (IProtocolFeeController);
}
