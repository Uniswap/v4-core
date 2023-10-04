// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Currency} from "../types/Currency.sol";

interface IFees {
    /// @notice Thrown when the protocol fee denominator is less than 4. Also thrown when the static or dynamic fee on a pool is exceeds 100%.
    error FeeTooLarge();
    /// @notice Thrown when not enough gas is provided to look up the protocol fee
    error ProtocolFeeCannotBeFetched();

    event ProtocolFeeControllerUpdated(address protocolFeeController);

    /// @notice Returns the minimum denominator for the protocol fee, which restricts it to a maximum of 25%
    function MIN_PROTOCOL_FEE_DENOMINATOR() external view returns (uint8);

    /// @notice Given a currency address, returns the protocol fees accrued in that currency
    function protocolFeesAccrued(Currency) external view returns (uint256);

    /// @notice Given a hook and a currency address, returns the fees accrued
    function hookFeesAccrued(address, Currency) external view returns (uint256);
}
