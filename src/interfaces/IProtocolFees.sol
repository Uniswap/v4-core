// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Currency} from "../types/Currency.sol";
import {IProtocolFeeController} from "../interfaces/IProtocolFeeController.sol";
import {PoolId} from "../types/PoolId.sol";
import {PoolKey} from "../types/PoolKey.sol";

interface IProtocolFees {
    /// @notice Thrown when not enough gas is provided to look up the protocol fee
    error ProtocolFeeCannotBeFetched();
    /// @notice Thrown when the call to fetch the protocol fee reverts or returns invalid data.
    error ProtocolFeeControllerCallFailedOrInvalidResult();

    /// @notice Thrown when collectProtocolFees is not called by the controller.
    error InvalidCaller();

    event ProtocolFeeControllerUpdated(address protocolFeeController);

    event ProtocolFeeUpdated(PoolId indexed id, uint24 protocolFee);

    /// @notice Given a currency address, returns the protocol fees accrued in that currency
    function protocolFeesAccrued(Currency) external view returns (uint256);

    /// @notice Sets the protocol's swap fee for the given pool
    /// Protocol fees are always a portion of the LP swap fee that is owed. If that fee is 0, no protocol fees will accrue even if it is set to > 0.
    function setProtocolFee(PoolKey memory key) external;

    /// @notice Sets the protocol fee controller
    function setProtocolFeeController(IProtocolFeeController) external;

    /// @notice Collects the protocol fees for a given recipient and currency, returning the amount collected
    function collectProtocolFees(address, Currency, uint256) external returns (uint256);

    function protocolFeeController() external view returns (IProtocolFeeController);
}
