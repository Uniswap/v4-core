// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IHooks} from "src/interfaces/IHooks.sol";
import {IPoolManager} from "src/interfaces/IPoolManager.sol";

import {Hooks} from "src/libraries/Hooks.sol";
import {TickMath} from "src/libraries/TickMath.sol";
import {Deployers} from "test/utils/Deployers.sol";
import {StateLibrary} from "src/libraries/StateLibrary.sol";
import {PoolId, PoolIdLibrary} from "src/types/PoolId.sol";
import {PoolKey} from "src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "src/types/Currency.sol";

import {PropertiesAsserts} from "../PropertiesHelper.sol";
import {SwapInfo, SwapInfoLibrary} from "./Lib.sol";

contract Harness is Deployers, PropertiesAsserts {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using SwapInfoLibrary for SwapInfo;

    uint256 constant MAX_CURRENCIES = 5;

    PoolId poolId;

    constructor() payable {
        Deployers.deployFreshManagerAndRouters();
    }

    function prop_CreatePool(int16 tickSpacing, uint256 startPrice, uint256 fee) public {
        if (address(Currency.unwrap(currency0)) != address(0)) {
            return;
        }

        int24 tickSpacingClamped = int24(clampBetween(tickSpacing, 1, type(int16).max));
        uint256 initialPrice = clampBetween(startPrice, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE);
        uint256 initialFee = clampBetween(fee, 0, 1_000_000);

        Deployers.deployMintAndApprove2Currencies();
        key = PoolKey(currency0, currency1, uint24(initialFee), tickSpacingClamped, IHooks(address(0)));
        poolId = key.toId();
        manager.initialize(key, uint160(initialPrice), ZERO_BYTES);

        modifyLiquidityRouter.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams(
                TickMath.minUsableTick(tickSpacingClamped), TickMath.maxUsableTick(tickSpacingClamped), 10_000 ether, 0
            ),
            ZERO_BYTES
        );

        // make sure the corpus contains some more extreme conditions
        uint256 leeway = 10;
        if (int256(tickSpacingClamped) < int256(leeway)) {
            emit LogInt256("tickSpacingClamped", tickSpacingClamped);
        } else if (int256(tickSpacingClamped) > int256(type(uint16).max - leeway)) {
            emit LogInt256("tickSpacingClamped", tickSpacingClamped);
        } else {
            emit LogInt256("tickSpacingClamped", tickSpacingClamped);
        }

        if (initialPrice < TickMath.MIN_SQRT_PRICE + leeway) {
            emit LogUint256("initialPrice", initialPrice);
        } else if (initialPrice > TickMath.MAX_SQRT_PRICE - leeway) {
            emit LogUint256("initialPrice", initialPrice);
        } else {
            emit LogUint256("initialPrice", initialPrice);
        }

        if (initialFee < leeway) {
            emit LogUint256("initialFee", initialFee);
        } else if (initialFee > 1_000_000 - leeway) {
            emit LogUint256("initialFee", initialFee);
        } else {
            emit LogUint256("initialFee", initialFee);
        }
    }

    // Swap into and out of a pair. ensure you're left with less tokens than you started with.
    // When swapping out of the pair, this function requests all the tokens it swapped in to be swapped back out.
    function prop_BiDirectionalPathExactInput(bool zeroForOne, int256 amount) public {
        if (address(Currency.unwrap(currency0)) == address(0)) {
            return;
        }
        Currency fromCurrency = zeroForOne ? currency0 : currency1;
        Currency toCurrency = zeroForOne ? currency1 : currency0;

        SwapInfo memory swap1Results = SwapInfoLibrary.initialize(fromCurrency, toCurrency, address(this));

        swap(key, zeroForOne, amount, ZERO_BYTES);

        swap1Results.captureSwapResults();

        emit LogInt256("Swap 1 amount", amount);
        emit LogInt256("Swap 1 fromDelta", swap1Results.fromDelta);
        emit LogInt256("Swap 1 toDelta", swap1Results.toDelta);

        assert(swap1Results.fromDelta <= 0);
        assert(swap1Results.toDelta >= 0);

        // now swap in the opposite direction using the exact amount we received
        int256 newAmount = -1 * swap1Results.toDelta;
        SwapInfo memory swap2Results = SwapInfoLibrary.initialize(toCurrency, fromCurrency, address(this));
        swap(key, !zeroForOne, newAmount, ZERO_BYTES);
        swap2Results.captureSwapResults();

        emit LogInt256("Swap 2 amount", newAmount);
        emit LogInt256("Swap 2 fromDelta", swap2Results.fromDelta);
        emit LogInt256("Swap 2 toDelta", swap2Results.toDelta);

        assert(swap2Results.fromDelta <= 0);
        assert(swap2Results.toDelta >= 0);

        // now actually verify the property
        int256 fromBalanceDifference = swap2Results.toBalanceAfter - swap1Results.fromBalanceBefore;
        int256 toBalanceDifference = swap2Results.fromBalanceAfter - swap1Results.toBalanceBefore;
        emit LogInt256("fromBalanceDifference", fromBalanceDifference);
        emit LogInt256("toBalanceDifference", toBalanceDifference);
        assertLt(fromBalanceDifference, 0, "Must not have more tokens than started with (from)");
        // re-add this if using a static newAmount
        assertLte(toBalanceDifference, 0, "Must not have more tokens than started with (to)");
    }

    // Swap into and out of a pair. ensure you're left with less tokens than you started with.
    function prop_BidirectionalPath(bool zeroForOne, int256 amount, uint128 reverseAmount) public {
        if (address(Currency.unwrap(currency0)) == address(0)) {
            return;
        }
        Currency fromCurrency = zeroForOne ? currency0 : currency1;
        Currency toCurrency = zeroForOne ? currency1 : currency0;

        SwapInfo memory swap1Results = SwapInfoLibrary.initialize(fromCurrency, toCurrency, address(this));

        swap(key, zeroForOne, amount, ZERO_BYTES);

        swap1Results.captureSwapResults();

        emit LogInt256("Swap 1 amount", amount);
        emit LogInt256("Swap 1 fromDelta", swap1Results.fromDelta);
        emit LogInt256("Swap 1 toDelta", swap1Results.toDelta);

        assert(swap1Results.fromDelta <= 0);
        assert(swap1Results.toDelta >= 0);

        // now swap in the opposite direction using exact input between 1 and the original swapped amount.
        int256 newAmount = -1 * int256(clampBetween(reverseAmount, 1, uint256(swap1Results.toDelta)));
        SwapInfo memory swap2Results = SwapInfoLibrary.initialize(toCurrency, fromCurrency, address(this));
        swap(key, !zeroForOne, newAmount, ZERO_BYTES);
        swap2Results.captureSwapResults();

        emit LogInt256("Swap 2 amount", newAmount);
        emit LogInt256("Swap 2 fromDelta", swap2Results.fromDelta);
        emit LogInt256("Swap 2 toDelta", swap2Results.toDelta);

        assert(swap2Results.fromDelta <= 0);
        assert(swap2Results.toDelta >= 0);

        // now actually verify the property
        int256 fromBalanceDifference = swap2Results.toBalanceAfter - swap1Results.fromBalanceBefore;
        int256 toBalanceDifference = swap2Results.fromBalanceAfter - swap1Results.toBalanceBefore;
        emit LogInt256("fromBalanceDifference", fromBalanceDifference);
        emit LogInt256("toBalanceDifference", toBalanceDifference);
        assertLt(fromBalanceDifference, 0, "Must not have more tokens than started with (from)");
    }
}
