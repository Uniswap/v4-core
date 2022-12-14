// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.15;
import {IPoolManager} from '../interfaces/IPoolManager.sol';
import {SafeCast} from './SafeCast.sol';
import {Currency} from './CurrencyLibrary.sol';
import {CurrencyDelta, CurrencyDeltaMapping} from './CurrencyDelta.sol';

library Commands {
    using SafeCast for int256;
    using CurrencyDeltaMapping for CurrencyDelta[];

    bytes1 internal constant SWAP = 0x00;
    bytes1 internal constant MODIFY = 0x01;
    bytes1 internal constant DONATE = 0x02;
    bytes1 internal constant TAKE = 0x03;
    bytes1 internal constant MINT = 0x04;

    // amount programming values
    uint256 constant ABS_DELTA = 0;

    // swap amountSpecified needs to keep the sign to differentiate exactIn and exactOut
    int256 constant EXACT_INPUT_ABS_DELTA = type(int256).max;
    int256 constant EXACT_OUTPUT_ABS_DELTA = type(int256).min;

    /// @notice map the given amount to if special delta identifier is provided
    /// @dev useful if the caller wants to take / mint all owed tokens
    function mapAmount(
        CurrencyDelta[] memory deltas,
        Currency currency,
        uint256 amount
    ) internal pure returns (uint256 mapped) {
        if (amount == ABS_DELTA) return deltas.get(currency).absToUint256();
        return amount;
    }

    /// @notice map the given swap params amountSpecified if special identifiers are provided
    /// @dev callers can request to use the current delta value, i.e. to swap all owed tokens
    /// or swap to exactly pay off a debt
    function mapAmount(
        CurrencyDelta[] memory deltas,
        IPoolManager.PoolKey memory key,
        IPoolManager.SwapParams memory params
    ) internal view {
        bool zeroForOne = params.zeroForOne;
        int256 amountSpecified = params.amountSpecified;
        if (amountSpecified == EXACT_INPUT_ABS_DELTA) {
            int256 delta = zeroForOne ? deltas.get(key.currency0) : deltas.get(key.currency1);
            params.amountSpecified = int256(delta.absToUint256());
        } else if (amountSpecified == EXACT_OUTPUT_ABS_DELTA) {
            int256 delta = zeroForOne ? deltas.get(key.currency1) : deltas.get(key.currency0);
            params.amountSpecified = -int256(delta.absToUint256());
        }
    }
}
