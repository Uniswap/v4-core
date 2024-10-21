// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ActionFuzzBase, ActionCallbacks} from "test/trailofbits/ActionFuzzBase.sol";
import {PoolId, PoolIdLibrary} from "src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "src/types/Currency.sol";
import {PoolKey} from "src/types/PoolKey.sol";
import {Actions} from "src/test/ActionsRouter.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "src/types/BalanceDelta.sol";
import {IHooks} from "src/interfaces/IHooks.sol";
import {StateLibrary} from "src/libraries/StateLibrary.sol";
import {IPoolManager} from "src/interfaces/IPoolManager.sol";
import {TransientStateLibrary} from "src/libraries/TransientStateLibrary.sol";
import {TickMath} from "src/libraries/TickMath.sol";
import {SwapMath} from "src/libraries/SwapMath.sol";
import {FullMath} from "src/libraries//FullMath.sol";
import {ProtocolFeeLibrary} from "src/libraries/ProtocolFeeLibrary.sol";
import {FixedPoint128} from "src/libraries/FixedPoint128.sol";

contract SwapActionProps is ActionFuzzBase {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;
    using ProtocolFeeLibrary for uint16;

    bool _swapZeroForOne;
    int256 _swapAmountSpecified;
    PoolKey _swapPoolKey;
    uint160 _swapPriceLimit;
    int24 _swapTickBefore;
    uint24 _swapLpFee;
    uint24 _swapProtocolFee;
    uint160 _swapSqrtPriceX96Before;
    int256 _swapCurrencyDelta0Before;
    int256 _swapCurrencyDelta1Before;
    uint128 _swapLiquidityBefore;
    uint256 _swapFeeGrowthGlobal0X128Before;
    uint256 _swapFeeGrowthGlobal1X128Before;
    uint256 _swapProtocolFees0;
    uint256 _swapProtocolFees1;

    uint256 _swapExpectedProtocolFee;
    uint256 _swapExpectedLpFee;

    function _addSwap(bool zeroForOne, int256 amountSpecified, PoolKey memory pk, uint160 priceLimit) internal {
        bytes memory swapParam = abi.encode(zeroForOne, amountSpecified, pk, priceLimit);

        bytes memory beforeSwapCbParam = _encodeHarnessCallback(ActionCallbacks.BEFORE_SWAP, swapParam);
        actions.push(Actions.HARNESS_CALLBACK);
        params.push(beforeSwapCbParam);

        actions.push(Actions.SWAP);
        params.push(swapParam);

        bytes memory afterSwapCbParam = _encodeHarnessCallback(ActionCallbacks.AFTER_SWAP, new bytes(0));
        actions.push(Actions.HARNESS_CALLBACK);
        params.push(afterSwapCbParam);
    }

    function addSwap(uint8 poolIdx, int256 amountSpecified, bool zeroForOne) public {
        PoolKey memory pk = _clampToValidPool(poolIdx);
        uint160 priceLimit = zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT;
        _addSwap(zeroForOne, amountSpecified, pk, priceLimit);
    }

    function _beforeSwap(bytes memory preSwapParam) internal {
        (_swapZeroForOne, _swapAmountSpecified, _swapPoolKey, _swapPriceLimit) =
            abi.decode(preSwapParam, (bool, int256, PoolKey, uint160));
        (_swapSqrtPriceX96Before, _swapTickBefore, _swapProtocolFee, _swapLpFee) = manager.getSlot0(_swapPoolKey.toId());

        _swapCurrencyDelta0Before = manager.currencyDelta(address(actionsRouter), _swapPoolKey.currency0);
        _swapCurrencyDelta1Before = manager.currencyDelta(address(actionsRouter), _swapPoolKey.currency1);

        emit LogInt256("currency 0 delta before swap", _swapCurrencyDelta0Before);
        emit LogInt256("currency 1 delta before swap", _swapCurrencyDelta1Before);
        emit LogUint256("sqrt price of pool before swap", _swapSqrtPriceX96Before);
        emit LogUint256("sqrt price limit", _swapPriceLimit);

        _swapLiquidityBefore = manager.getLiquidity(_swapPoolKey.toId());
        (_swapFeeGrowthGlobal0X128Before, _swapFeeGrowthGlobal1X128Before) =
            manager.getFeeGrowthGlobals(_swapPoolKey.toId());

        _swapProtocolFees0 = manager.protocolFeesAccrued(_swapPoolKey.currency0);
        _swapProtocolFees1 = manager.protocolFeesAccrued(_swapPoolKey.currency1);
        emit LogUint256("initial protocol fees collected amount0", _swapProtocolFees0);
        emit LogUint256("initial protocol fees collected amount1", _swapProtocolFees1);

        (_swapExpectedProtocolFee, _swapExpectedLpFee) =
            _calculateExpectedLPAndProtocolFees(_swapPoolKey, _swapZeroForOne, _swapAmountSpecified, _swapPriceLimit);

        _verifyGlobalProperties(address(actionsRouter), _swapPoolKey.currency0);
        _verifyGlobalProperties(address(actionsRouter), _swapPoolKey.currency1);
    }

    function _afterSwap(BalanceDelta delta) internal {
        emit LogInt256("amount0 balanceDelta", delta.amount0());
        emit LogInt256("amount1 balanceDelta", delta.amount1());

        /* Properties for the pool's slot0 and how its values have changed */
        (uint160 newPrice, int24 newTick,,) = manager.getSlot0(_swapPoolKey.toId());
        _verifySlot0Properties(newPrice, newTick);

        /* Fee properties */
        _verifyFeeProperties(delta, newTick);

        /* Properties for what we expect has not changed */
        uint128 newLiquidity = manager.getLiquidity(_swapPoolKey.toId());
        if (newTick == _swapTickBefore) {
            // UNI-SWAP-1 (hehe)
            assertEq(
                newLiquidity,
                _swapLiquidityBefore,
                "After a swap, if the pool's active tick did not change, its liquidity must be the same as it was before the swap."
            );
        }

        /* Boundary conditions of swap() */
        _verifyBoundaryProperties(newPrice, newTick);

        /* Verify the key properties of swap() */
        _verifySwapBehavior(delta, newPrice, newTick);

        /* Update our ledger of virtual pool reserves */
        _updateSwapBalances(delta);

        /* These props needs to be verified at the end of the updates */
        _verifyGlobalProperties(address(actionsRouter), _swapPoolKey.currency0);
        _verifyGlobalProperties(address(actionsRouter), _swapPoolKey.currency1);
    }

    function _verifySlot0Properties(uint160 newPrice, int24 newTick) internal {
        emit LogUint256("new pool price", newPrice);
        if (_swapZeroForOne) {
            // TODO: see if we can get this more restrictive (lte => lt), or even eq
            // UNI-SWAP-2
            assertLte(
                newPrice,
                _swapSqrtPriceX96Before,
                "The pool's sqrtPriceX96 should decrease or stay the same after making a zeroForOne swap."
            );
            // UNI-SWAP-4
            assertGte(
                newPrice,
                _swapPriceLimit,
                "The pool's new sqrtPriceX96 must not be lower than the transaction's price limit after making a zeroForOne swap."
            );
            // UNI-SWAP-6
            assertLte(
                newTick,
                _swapTickBefore,
                "The pool's active tick should decrease or stay the same after making a zeroForOne swap."
            );

            if (_swapTickBefore - newTick >= 1) {
                emit LogString("Successfully crossed multiple ticks in same tx, moving lower");
            } else if (_swapTickBefore == newTick) {
                emit LogString("Successfully stayed in the same tick while moving lower");
            }
        } else {
            // TODO: see if we can get this more restrictive (gte => gt), or even eq
            // UNI-SWAP-3
            assertGte(
                newPrice,
                _swapSqrtPriceX96Before,
                "The pool's sqrtPriceX96 should increase or stay the same after making a oneForZero swap."
            );
            // UNI-SWAP-5
            assertLte(
                newPrice,
                _swapPriceLimit,
                "The pool's new sqrtPriceX96 must not exceed the transaction's price limit after making a oneForZero swap."
            );
            // UNI-SWAP-7
            assertGte(
                newTick,
                _swapTickBefore,
                "The pool's active tick should increase or stay the same after making a oneForZero swap."
            );

            if (newTick - _swapTickBefore >= 1) {
                emit LogString("Successfully crossed multiple ticks in same tx, moving higher");
            } else if (_swapTickBefore == newTick) {
                emit LogString("Successfully stayed in the same tick while moving lower");
            }
        }
    }

    function _getNumCrossedTicks(int24 oldTick, int24 newTick) internal pure returns (uint256) {
        if (oldTick > newTick) {
            return uint256(int256(oldTick - newTick));
        } else {
            return uint256(int256(newTick - oldTick));
        }
    }

    function _verifyFeeProperties(BalanceDelta, int24) internal {
        /* Properties for how the fees have changed */
        (,, uint24 newProtocolFee, uint24 newLpFee) = manager.getSlot0(_swapPoolKey.toId());
        (uint256 newSwapFeeGrowth0X128, uint256 newSwapFeeGrowth1X128) =
            manager.getFeeGrowthGlobals(_swapPoolKey.toId());

        uint256 swapFee = newProtocolFee == 0 ? newLpFee : uint16(newProtocolFee).calculateSwapFee(newLpFee);
        emit LogUint256("swap fee", swapFee);
        //uint256 numTicksCrossed = _getNumCrossedTicks(newTick, _swapTickBefore);

        if (_swapZeroForOne) {
            // UNI-SWAP-8
            assertEq(
                newSwapFeeGrowth1X128,
                _swapFeeGrowthGlobal1X128Before,
                "After a zeroForOne swap, the fee growth for currency1 should not change."
            );

            // for now, we can only validate the following props when numTicksCrossed == 0. This is because when multiple ticks are crossed,
            // we need to get the liquidity at each tick crossed and figure out how much of the tick was consumed.
            // This is totally possible, but has to be saved for future work.
            /*
            if (true) {
                uint256 theoreticalFee = FullMath.mulDivRoundingUp(uint256(int256(-delta.amount0())), swapFee, SwapMath.MAX_FEE_PIPS);
                uint256 expectedFeeGrowthDeltaX128 = FullMath.mulDiv(theoreticalFee, FixedPoint128.Q128, _swapLiquidityBefore);
                //uint256 expectedFeeGrowth = _calculateExpectedFeeGrowth(expectedFeeGrowthDeltaX128, _swapFeeGrowthGlobal0X128Before);
                // UNI-SWAP-10 (remove)
                //assertEq(expectedFeeGrowth, newSwapFeeGrowth0X128, "After a zeroForOneSwap, the fee growth for currency0 should match the expected fee growth.");
            }
            */
        } else {
            // UNI-SWAP-9
            assertEq(
                newSwapFeeGrowth0X128,
                _swapFeeGrowthGlobal0X128Before,
                "After a oneForZero swap, the fee growth for currency0 should not change."
            );
            /*
            if (true) {
                uint256 theoreticalFee = FullMath.mulDivRoundingUp(uint256(int256(-delta.amount1())), swapFee, SwapMath.MAX_FEE_PIPS);
                emit LogUint256("swap liquidity", _swapLiquidityBefore);
                uint256 expectedFeeGrowthDeltaX128 = FullMath.mulDiv(theoreticalFee, FixedPoint128.Q128, _swapLiquidityBefore);
                emit LogUint256("prev fee growth", _swapFeeGrowthGlobal1X128Before);
                emit LogUint256("theoretical fee", theoreticalFee);
                emit LogUint256("expectedFeeGrowthDeltaX128", expectedFeeGrowthDeltaX128);
                //uint256 expectedFeeGrowth = _calculateExpectedFeeGrowth(expectedFeeGrowthDeltaX128, _swapFeeGrowthGlobal1X128Before);
                // UNI-SWAP-11 (remove)
                //assertEq(expectedFeeGrowth, newSwapFeeGrowth1X128, "After a oneForZero, the fee growth for currency1 should match the expected fee growth. ");
            }
            */
        }
    }

    function _verifyBoundaryProperties(uint160 newPrice, int24 newTick) internal {
        // UNI-SWAP-10
        assertNeq(_swapAmountSpecified, 0, "The swap action must revert if swap amount is zero.");
        // UNI-SWAP-11
        assertLt(newPrice, TickMath.MAX_SQRT_PRICE, "The pool's new price must be less than MAX_SQRT_PRICE");
        // UNI-SWAP-12
        assertGt(
            newPrice, TickMath.MIN_SQRT_PRICE, "The pool's new price must be greater than or equal to MIN_SQRT_PRICE"
        );
        // UNI-SWAP-13
        assertLte(newTick, TickMath.MAX_TICK, "The pool's new tick must be less than or equal to MAX_TICK");
        // UNI-SWAP-14
        assertGte(newTick, TickMath.MIN_TICK, "The pool's new tick must be greater than or equal to MIN_TICK");
    }

    function _verifySwapBehavior(BalanceDelta delta, uint160 newPrice, int24) internal {
        int256 currencyDelta0After = manager.currencyDelta(address(actionsRouter), _swapPoolKey.currency0);
        int256 currencyDelta1After = manager.currencyDelta(address(actionsRouter), _swapPoolKey.currency1);

        /* Properties of swap()'s behavior */
        // We use fromBalanceDelta/toBalanceDelta to reduce the number of properties. There's no need to if(zeroForOne) constantly.
        // The assumptions introduced by using this abstraction are checked in SWAP-PROP-17/SWAP-PROP-18.
        int128 fromBalanceDelta = _swapZeroForOne ? delta.amount0() : delta.amount1();
        int128 toBalanceDelta = _swapZeroForOne ? delta.amount1() : delta.amount0();
        int256 fromCurrencyDeltaFull;
        int256 toCurrencyDeltaFull;
        if (_swapZeroForOne) {
            fromCurrencyDeltaFull = manager.currencyDelta(address(actionsRouter), _swapPoolKey.currency0);
            toCurrencyDeltaFull = manager.currencyDelta(address(actionsRouter), _swapPoolKey.currency1);
            emit LogString("zeroForOne");
        } else {
            fromCurrencyDeltaFull = manager.currencyDelta(address(actionsRouter), _swapPoolKey.currency1);
            toCurrencyDeltaFull = manager.currencyDelta(address(actionsRouter), _swapPoolKey.currency0);
            emit LogString("oneforzero");
        }
        emit LogInt256("fromBalanceDelta", fromBalanceDelta);
        emit LogInt256("toBalanceDelta", toBalanceDelta);
        emit LogInt256("currencyDelta0After", currencyDelta0After);
        emit LogInt256("currencyDelta1After", currencyDelta1After);
        emit LogInt256("_swapAmountSpecified", _swapAmountSpecified);

        if (fromBalanceDelta != 0 && toBalanceDelta != 0) {
            // UNI-SWAP-15 transitive; Swaps respect the sqrtPriceLimit ahead of the need to consume exactInput or exactOutput.
            if (_swapPriceLimit != newPrice) {
                if (_swapAmountSpecified < 0) {
                    // exact input
                    // UNI-SWAP-16, iff the price limit was not reached
                    assertEq(
                        fromBalanceDelta,
                        _swapAmountSpecified,
                        "For exact input swaps where the price limit is not reached, the fromBalanceDelta must match the exact input amount."
                    );
                } else {
                    // exact output
                    // UNI-SWAP-17, iff the price limit was not reached
                    assertEq(
                        toBalanceDelta,
                        _swapAmountSpecified,
                        "For exact output swaps where the price limit is not reached, the toBalanceDelta must match the exact output amount."
                    );
                }
            } else {
                // todo: use lte/gte to ensure price limit was not exceeded
            }
        } else {
            // One or both of the deltas being zero should be a result of rounding down to zero, but there is still a case we need to check for.
            if (fromBalanceDelta == 0) {
                // UNI-SWAP-18
                assertEq(
                    toBalanceDelta,
                    0,
                    "If the fromBalanceDelta of a swap is zero, the toBalanceDelta must also be zero (rounding)."
                );
            }
        }

        /* Properties of the system's currencyDeltas and how it compares to balanceDelta */
        // UNI-SWAP-19
        assertGte(toBalanceDelta, 0, "For any swap, the amount credited to the user is greater than or equal to zero.");
        // UNI-SWAP-20
        assertLte(fromBalanceDelta, 0, "For any swap, the amount credited to the user is less than or equal to zero");

        int256 expectedDelta0After = _swapCurrencyDelta0Before + delta.amount0();
        int256 expectedDelta1After = _swapCurrencyDelta1Before + delta.amount1();

        // if our deltas are bigger than the liquidity that was in the pool, this action is stealing tokens from another pool.
        if (_swapZeroForOne) {
            // UNI-SWAP-21
            assertLte(
                int256(delta.amount1()),
                PoolLiquidities[_swapPoolKey.toId()].amount1,
                "For a zeroForOne swap, the amount credited to the user must be less than or equal to the total number of tradeable tokens in the pool"
            );
        } else {
            // UNI-SWAP-22
            assertLte(
                int256(delta.amount0()),
                PoolLiquidities[_swapPoolKey.toId()].amount0,
                "For a oneForZero swap, the amount credited to the user must be less than or equal to the total number of tradeable tokens in the pool"
            );
        }

        // UNI-SWAP-23
        assertEq(
            currencyDelta0After,
            expectedDelta0After,
            "After a swap, the user's currencyDelta for amount0 should match the expected delta based on BalanceDelta."
        );
        // UNI-SWAP-24
        assertEq(
            currencyDelta1After,
            expectedDelta1After,
            "After a swap, the user's currencyDelta for amount1 should match the expected delta based on BalanceDelta."
        );
    }

    function _updateSwapBalances(BalanceDelta delta) internal {
        emit LogInt256("cur0 BalanceDelta from swap", delta.amount0());
        emit LogInt256("cur1 BalanceDelta from swap", delta.amount1());

        int256 expectedLpFee0;
        int256 expectedLpFee1;

        if (_swapZeroForOne) {
            expectedLpFee0 = int256(_swapExpectedLpFee);
            SingletonLPFees[_swapPoolKey.currency0] += _swapExpectedLpFee;
            emit LogUint256("new singleton LP fees (amount0)", SingletonLPFees[_swapPoolKey.currency0]);
        } else {
            expectedLpFee1 = int256(_swapExpectedLpFee);
            SingletonLPFees[_swapPoolKey.currency1] += _swapExpectedLpFee;
            emit LogUint256("new singleton LP fees (amount1)", SingletonLPFees[_swapPoolKey.currency1]);
        }

        {
            uint256 protocolFeesLevied0 = (manager.protocolFeesAccrued(_swapPoolKey.currency0) - (_swapProtocolFees0));
            uint256 protocolFeesLevied1 = (manager.protocolFeesAccrued(_swapPoolKey.currency1) - (_swapProtocolFees1));

            emit LogUint256("protocol fees levied amount0", protocolFeesLevied0);
            emit LogUint256("protocol fees levied amount1", protocolFeesLevied1);

            emit LogInt256("prev pool liquidity amount0", PoolLiquidities[_swapPoolKey.toId()].amount0);
            emit LogInt256("prev pool liquidity amount1", PoolLiquidities[_swapPoolKey.toId()].amount1);

            PoolLiquidities[_swapPoolKey.toId()].amount0 -=
                delta.amount0() + int256(protocolFeesLevied0) + expectedLpFee0;
            PoolLiquidities[_swapPoolKey.toId()].amount1 -=
                delta.amount1() + int256(protocolFeesLevied1) + expectedLpFee1;
            emit LogInt256("new pool liquidity amount0", PoolLiquidities[_swapPoolKey.toId()].amount0);
            emit LogInt256("new pool liquidity amount1", PoolLiquidities[_swapPoolKey.toId()].amount1);

            // Update singleton liquidity, remove the amount sent/recvd from user.
            uint256 newSingletonLiq0 = _deltaAdd(SingletonLiquidity[_swapPoolKey.currency0], -(delta.amount0()));
            uint256 newSingletonLiq1 = _deltaAdd(SingletonLiquidity[_swapPoolKey.currency1], -(delta.amount1()));

            // Update singleton liquidity, remove the amount consumed by protocol.
            newSingletonLiq0 = _deltaAdd(newSingletonLiq0, -int256(protocolFeesLevied0));
            newSingletonLiq1 = _deltaAdd(newSingletonLiq1, -int256(protocolFeesLevied1));

            newSingletonLiq0 = _deltaAdd(newSingletonLiq0, -int256(expectedLpFee0));
            newSingletonLiq1 = _deltaAdd(newSingletonLiq1, -int256(expectedLpFee1));

            SingletonLiquidity[_swapPoolKey.currency0] = newSingletonLiq0;
            SingletonLiquidity[_swapPoolKey.currency1] = newSingletonLiq1;

            _updateCurrencyDelta(address(actionsRouter), _swapPoolKey.currency0, delta.amount0());
            _updateCurrencyDelta(address(actionsRouter), _swapPoolKey.currency1, delta.amount1());
        }
    }
}
