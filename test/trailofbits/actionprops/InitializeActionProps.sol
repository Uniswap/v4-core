// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ActionFuzzBase} from "test/trailofbits/ActionFuzzBase.sol";
import {PoolId, PoolIdLibrary} from "src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "src/types/Currency.sol";
import {PoolKey} from "src/types/PoolKey.sol";
import {Actions} from "src/test/ActionsRouter.sol";
import {IHooks} from "src/interfaces/IHooks.sol";
import {StateLibrary} from "src/libraries/StateLibrary.sol";
import {TickMath} from "src/libraries/TickMath.sol";
import {Pool} from "src/libraries/Pool.sol";
import {LPFeeLibrary} from "src/libraries/LPFeeLibrary.sol";
import {ProtocolFeeLibrary} from "src/libraries/ProtocolFeeLibrary.sol";
import {IPoolManager} from "src/interfaces/IPoolManager.sol";

contract InitializeActionProps is ActionFuzzBase {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    function addInitialize(uint8 currency1I, uint8 currency2I, int24 tickSpacing, uint160 startPrice, uint24 fee)
        public
    {
        Currency c1;
        Currency c2;
        (c1, c2) = _clampToValidCurrencies(currency1I, currency2I);
        int24 tickSpacingClamped =
            int24(clampBetween(tickSpacing, TickMath.MIN_TICK_SPACING, TickMath.MAX_TICK_SPACING));
        emit LogInt256("tickSpacingClamped", tickSpacingClamped);

        uint256 initialPrice = clampBetween(startPrice, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE - 1);
        emit LogUint256("initialPrice", initialPrice);

        uint256 initialFee = clampBetween(fee, 0, ProtocolFeeLibrary.PIPS_DENOMINATOR);
        emit LogUint256("initialFee", initialFee);

        PoolKey memory k = PoolKey(c1, c2, uint24(initialFee), tickSpacingClamped, IHooks(address(0)));
        PoolId id = k.toId();
        require(!PoolInitialized[id]);
        // todo: add revert catcher from e2e harness
        try manager.initialize(k, uint160(initialPrice), new bytes(0)) {}
        catch (bytes memory b) {
            emit LogBytes(b);
            // UNI-INIT-1
            assertWithMsg(
                false,
                "initialize() should not revert when it is passed valid parameters (tick spacing, price, fee, pool key,  non-existing poo)"
            );
        }

        DeployedPools.push(k);
        PoolInitialized[id] = true;
    }

    function addInitializeUnconstrained(
        uint8 currency1I,
        uint8 currency2I,
        int24 tickSpacing,
        uint160 startPrice,
        uint24 fee
    ) public {
        Currency c1;
        Currency c2;
        (c1, c2) = _clampToValidCurrencies(currency1I, currency2I);

        PoolKey memory k = PoolKey(c1, c2, uint24(fee), tickSpacing, IHooks(address(0)));
        PoolId id = k.toId();

        bool poolinitialized = PoolInitialized[id];
        int24 tick;

        try manager.initialize(k, uint160(startPrice), new bytes(0)) returns (int24 t) {
            tick = t;
        } catch (bytes memory data) {
            // UNI-INIT-2
            if (bytes4(data) == Pool.PoolAlreadyInitialized.selector) {
                // allowable exception iff poolInitialized
                assertWithMsg(
                    poolinitialized,
                    "initialize() must not throw PoolAlreadyInitialized() when there is no pre-existing pool initialized with the same PoolKey"
                );
                return;
            }
            // UNI-INIT-3
            if (bytes4(data) == TickMath.InvalidSqrtPrice.selector) {
                // allowable exception iff initialPrice is outside the valid range
                assertWithMsg(
                    startPrice < TickMath.MIN_SQRT_PRICE || startPrice > TickMath.MAX_SQRT_PRICE - 1,
                    "initialize() must not throw InvalidSqrtPrice() when provided a price within the valid range"
                );
                return;
            }
            // UNI-INIT-4
            if (bytes4(data) == LPFeeLibrary.LPFeeTooLarge.selector) {
                // allowable exception iff fee is larger than 1_000_000
                assertGt(
                    fee, 1_000_000, "initialize() must not throw LPFeeTooLarge() when the fee is in the valid range"
                );
                return;
            }

            // UNI-INIT-5
            if (bytes4(data) == IPoolManager.TickSpacingTooLarge.selector) {
                // allowable exception iff tick spacing is >max
                assertGt(
                    tickSpacing,
                    TickMath.MAX_TICK_SPACING,
                    "initialize() must not throw TickSpacingTooLarge() when the tick spacing is in the valid range"
                );
                return;
            }

            // UNI-INIT-6
            if (bytes4(data) == IPoolManager.TickSpacingTooSmall.selector) {
                // allowable exception iff tick spacing is <min
                assertLt(
                    tickSpacing,
                    TickMath.MIN_TICK_SPACING,
                    "initialize() must not throw TickSpacingTooSmall() when the tick spacing is in the valid range"
                );
                return;
            }
            // todo: revisit for other types of errors
            require(false);
        }

        // UNI-INIT-7
        assertWithMsg(!poolinitialized, "initialize() must revert if the provided pool key is already initialized");
        // UNI-INIT-8
        assertGte(
            tick,
            TickMath.MIN_TICK,
            "initialize() must construct a pool whose tick is greater than or equal to MIN_TICK"
        );
        // UNI-INIT-9
        assertLte(
            tick, TickMath.MAX_TICK, "initialize() must construct a pool whose tick is less than or equal to MAX_TICK"
        );

        (uint160 price,,,) = manager.getSlot0(id);
        // UNI-INIT-10
        assertNeq(price, 0, "initialize() must never create a pool with an initial sqrtPrice of zero.");

        DeployedPools.push(k);
        PoolInitialized[id] = true;
    }
}
