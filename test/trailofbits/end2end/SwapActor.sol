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
import {PoolModifyLiquidityTest} from "src/test/PoolModifyLiquidityTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {IActor} from "./IActor.sol";
import {BalanceDelta} from "src/types/BalanceDelta.sol";
import {CurrencySettler} from "test/utils/CurrencySettler.sol";
import {PoolTestBase} from "src/test/PoolTestBase.sol";
import {LPFeeLibrary} from "src/libraries/LPFeeLibrary.sol";
import {SwapInfo, SwapInfoLibrary} from "./Lib.sol";

contract SwapActor is PropertiesAsserts, PoolTestBase, IActor {

    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;
    using Hooks for IHooks;
    using LPFeeLibrary for uint24;

    uint160 internal constant MIN_PRICE_LIMIT = TickMath.MIN_SQRT_PRICE + 1;
    uint160 internal constant MAX_PRICE_LIMIT = TickMath.MAX_SQRT_PRICE - 1;

    address Harness;

    constructor(IPoolManager _manager) PoolTestBase(_manager) {
        Harness = msg.sender;
    }

    function proxyApprove(Currency token, address spender) public {
        MockERC20(Currency.unwrap(token)).approve(spender, type(uint256).max);
    }

    struct TestSettings {
        bool takeClaims;
        bool settleUsingBurn;
    }

    /// @custom:property After a swap, the actor's fromFunds should decrease or not change, and their toFunds should increase or not change.
    /// @custom:precondition PoolKey is an initialized pool.
    /// @custom:notes 
    function swapOneDirection(bool zeroForOne, int256 amount, PoolKey memory poolKey) public returns (SwapInfo memory) {
        Currency fromCurrency = zeroForOne ? poolKey.currency0 : poolKey.currency1;
        Currency toCurrency = zeroForOne ? poolKey.currency1 : poolKey.currency0;
        SwapInfo memory swap1Results = SwapInfoLibrary.initialize(fromCurrency, toCurrency, address(Harness));

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: amount,
                sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
            });
        TestSettings memory settings = TestSettings({takeClaims: false, settleUsingBurn: false});

        abi.decode(
            manager.unlock(abi.encode(CallbackData(address(this), settings, poolKey, params, new bytes(0)))), (BalanceDelta)
        );

        swap1Results.captureSwapResults();
        emit LogInt256("a Swap amount", amount);
        emit LogInt256("a Swap fromDelta", swap1Results.fromDelta);
        emit LogInt256("a Swap toDelta", swap1Results.toDelta);

        assertWithMsg(swap1Results.fromDelta <= 0, "fromDelta <= 0");
        assertWithMsg(swap1Results.toDelta >= 0, "toDelta >= 0");

        return swap1Results;
    }

    /// @custom:property After a bi-directional swap, the actor's fromFunds should decrease and their toFunds should decrease or not change.
    /// @custom:precondition PoolKey is an initialized pool.
    /// @custom:notes 
    function swapBiDirectional(bool zeroForOne, int256 amount, PoolKey memory poolKey) public {
        if(amount < 0){
            amount = amount * -1;
        }
        SwapInfo memory swap1Results = swapOneDirection(zeroForOne, amount, poolKey);

        // now swap in the opposite direction using the exact amount we received
        int256 newAmount = -1 * swap1Results.toDelta;
        require(newAmount != 0);

        SwapInfo memory swap2Results = swapOneDirection(!zeroForOne, newAmount, poolKey);

        // now actually verify the property
        int256 fromBalanceDifference = swap2Results.toBalanceAfter - swap1Results.fromBalanceBefore;
        int256 toBalanceDifference = swap2Results.fromBalanceAfter - swap1Results.toBalanceBefore;
        emit LogInt256("fromBalanceDifference", fromBalanceDifference);
        emit LogInt256("toBalanceDifference", toBalanceDifference);

        assertLt(fromBalanceDifference, 0, "Must not have more tokens than started with (from)");
        assertLte(toBalanceDifference, 0, "Must not have more tokens than started with (to)");
    }
    
    struct CallbackData {
        address sender;
        TestSettings testSettings;
        PoolKey key;
        IPoolManager.SwapParams params;
        bytes hookData;
    }

    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));
        CallbackData memory data = abi.decode(rawData, (CallbackData));

        (,, int256 deltaBefore0) = _fetchBalances(data.key.currency0, data.sender, address(this));
        (,, int256 deltaBefore1) = _fetchBalances(data.key.currency1, data.sender, address(this));

        assertWithMsg(deltaBefore0 == 0, "deltaBefore0 is not equal to 0");
        assertWithMsg(deltaBefore1 == 0, "deltaBefore1 is not equal to 0");

        BalanceDelta delta = manager.swap(data.key, data.params, data.hookData);

        (,, int256 deltaAfter0) = _fetchBalances(data.key.currency0, data.sender, address(this));
        (,, int256 deltaAfter1) = _fetchBalances(data.key.currency1, data.sender, address(this));

        if (data.params.zeroForOne) {
            if (data.params.amountSpecified < 0) {
                // exact input, 0 for 1
                assertWithMsg(
                    deltaAfter0 >= data.params.amountSpecified,
                    "deltaAfter0 is not greater than or equal to data.params.amountSpecified"
                );
                assertWithMsg(delta.amount0() == deltaAfter0, "delta.amount0() is not equal to deltaAfter0");
                assertWithMsg(deltaAfter1 >= 0, "deltaAfter1 is not greater than or equal to 0");
            } else {
                // exact output, 0 for 1
                assertWithMsg(deltaAfter0 <= 0, "deltaAfter0 is not less than or equal to zero");
                assertWithMsg(delta.amount1() == deltaAfter1, "delta.amount1() is not equal to deltaAfter1");
                assertWithMsg(
                    deltaAfter1 <= data.params.amountSpecified,
                    "deltaAfter1 is not less than or equal to data.params.amountSpecified"
                );
            }
        } else {
            if (data.params.amountSpecified < 0) {
                // exact input, 1 for 0
                assertWithMsg(
                    deltaAfter1 >= data.params.amountSpecified,
                    "deltaAfter1 is not greater than or equal to data.params.amountSpecified"
                );
                assertWithMsg(delta.amount1() == deltaAfter1, "delta.amount1() is not equal to deltaAfter1");
                assertWithMsg(deltaAfter0 >= 0, "deltaAfter0 is not greater than or equal to 0");
            } else {
                // exact output, 1 for 0
                assertWithMsg(deltaAfter1 <= 0, "deltaAfter1 is not less than or equal to 0");
                assertWithMsg(delta.amount0() == deltaAfter0, "delta.amount0() is not equal to deltaAfter0");
                assertWithMsg(
                    deltaAfter0 <= data.params.amountSpecified,
                    "deltaAfter0 is not less than or equal to data.params.amountSpecified"
                );
            }
        }


        if (deltaAfter0 < 0) {
            // obtain tokens from harness
            MockERC20(Currency.unwrap(data.key.currency0)).transferFrom(Harness, address(this), uint256(-deltaAfter0));
            CurrencySettler.settle(data.key.currency0, manager, data.sender, uint256(-deltaAfter0), false);
        }
        if (deltaAfter1 < 0) {
            // obtain tokens from harness
            MockERC20(Currency.unwrap(data.key.currency1)).transferFrom(Harness, address(this), uint256(-deltaAfter1));
            CurrencySettler.settle(data.key.currency1, manager, data.sender, uint256(-deltaAfter1), false);
        }
        if (deltaAfter0 > 0) {
            CurrencySettler.take(data.key.currency0, manager, data.sender, uint256(deltaAfter0), false);
            // send tokens back to harness
            data.key.currency0.transfer(Harness, uint256(deltaAfter0));
        }
        if (deltaAfter1 > 0) {
            CurrencySettler.take(data.key.currency1, manager, data.sender, uint256(deltaAfter1), false);
            // send tokens back to harness
            data.key.currency1.transfer( Harness, uint256(deltaAfter1));
        }

        return abi.encode(delta);
    }
}