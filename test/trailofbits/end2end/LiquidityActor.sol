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
import {PoolModifyLiquidityTest} from "src/test/PoolModifyLiquidityTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {IActor} from "./IActor.sol";
import {BalanceDelta} from "src/types/BalanceDelta.sol";
import {CurrencySettler} from "test/utils/CurrencySettler.sol";
import {PoolTestBase} from "src/test/PoolTestBase.sol";
import {LPFeeLibrary} from "src/libraries/LPFeeLibrary.sol";

contract LiquidityActor is PropertiesAsserts, PoolTestBase, IActor {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;
    using Hooks for IHooks;
    using LPFeeLibrary for uint24;

    struct LpPosition {
        PoolKey poolKey;
        int24 minTick;
        int24 maxTick;
        uint256 liquidity;
        bytes32 salt;
    }

    mapping(PoolId => mapping(uint256 => LpPosition)) lpPositions;
    mapping(PoolId => uint256) lpPositionCount;
    address Harness;

    constructor(IPoolManager _manager) PoolTestBase(_manager) {
        Harness = msg.sender;
    }

    function _getLatestSalt(PoolId poolId) internal returns (uint256) {
        uint256 nextSalt = lpPositionCount[poolId];
        lpPositionCount[poolId] += 1;
        return nextSalt;
    }

    function ProvideLiquidity(PoolKey memory poolKey, int24 minTick, int24 maxTick, int256 liqDelta)
        public
        returns (uint256 delta0, uint256 delta1)
    {
        PoolId poolId = poolKey.toId();
        uint256 salt = _getLatestSalt(poolId);

        uint256 cur0Before = poolKey.currency0.balanceOf(msg.sender);
        uint256 cur1Before = poolKey.currency1.balanceOf(msg.sender);

        IPoolManager.ModifyLiquidityParams memory params =
            IPoolManager.ModifyLiquidityParams(minTick, maxTick, liqDelta, bytes32(salt));
        try manager.unlock(abi.encode(CallbackData(address(this), poolKey, params, new bytes(0), false, false))) {}
        catch Error(string memory reason) {
            emit LogString("Error in unlock");
            emit LogString(reason);
            assert(false);
        }
        emit LogUint256("Liquidity provided for position idx", salt);
        emit LogInt256("liquidity", liqDelta);
        delta0 = cur0Before - poolKey.currency0.balanceOf(msg.sender);
        delta1 = cur1Before - poolKey.currency1.balanceOf(msg.sender);
        emit LogUint256("currency 0 delta", delta0);
        emit LogUint256("currency 1 delta", delta1);
        LpPosition memory lpPosition = lpPositions[poolId][salt];

        // technically an invariant null-op since this function always creates new positions. Should also be verified in unlockCallback.
        assertGte(liqDelta + int256(lpPosition.liquidity), 0, "Removed more liquidity than was in the position");

        uint128 liquidity;
        (liquidity,,) = manager.getPositionInfo(poolId, address(this), minTick, maxTick, bytes32(salt));

        lpPositions[poolId][salt] = LpPosition(poolKey, minTick, maxTick, liquidity, bytes32(salt));
    }

    function proxyApprove(Currency token, address spender) public {
        MockERC20(Currency.unwrap(token)).approve(spender, type(uint256).max);
    }

    struct CallbackData {
        address sender;
        PoolKey key;
        IPoolManager.ModifyLiquidityParams params;
        bytes hookData;
        bool settleUsingBurn;
        bool takeClaims;
    }

    function unlockCallback(bytes calldata rawData) external override returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        uint128 liquidityBefore;
        (liquidityBefore,,) = manager.getPositionInfo(
            data.key.toId(), address(this), data.params.tickLower, data.params.tickUpper, data.params.salt
        );

        (BalanceDelta delta,) = manager.modifyLiquidity(data.key, data.params, data.hookData);

        uint128 liquidityAfter;
        (liquidityAfter,,) = manager.getPositionInfo(
            data.key.toId(), address(this), data.params.tickLower, data.params.tickUpper, data.params.salt
        );

        (,, int256 delta0) = _fetchBalances(data.key.currency0, data.sender, address(this));
        (,, int256 delta1) = _fetchBalances(data.key.currency1, data.sender, address(this));

        require(
            int128(liquidityBefore) + data.params.liquidityDelta == int128(liquidityAfter), "liquidity change incorrect"
        );

        if (data.params.liquidityDelta < 0) {
            assert(delta0 > 0 || delta1 > 0);
            assert(!(delta0 < 0 || delta1 < 0));
        } else if (data.params.liquidityDelta > 0) {
            assert(delta0 < 0 || delta1 < 0);
            assert(!(delta0 > 0 || delta1 > 0));
        }

        if (delta0 < 0) {
            // obtain tokens from harness
            MockERC20(Currency.unwrap(data.key.currency0)).transferFrom(Harness, address(this), uint256(-delta0));
            CurrencySettler.settle(data.key.currency0, manager, data.sender, uint256(-delta0), data.settleUsingBurn);
        }
        if (delta1 < 0) {
            // obtain tokens from harness
            MockERC20(Currency.unwrap(data.key.currency1)).transferFrom(Harness, address(this), uint256(-delta1));
            CurrencySettler.settle(data.key.currency1, manager, data.sender, uint256(-delta1), data.settleUsingBurn);
        }
        if (delta0 > 0) {
            CurrencySettler.take(data.key.currency0, manager, data.sender, uint256(delta0), data.takeClaims);
            // send tokens back to harness
            data.key.currency0.transfer(Harness, uint256(delta0));
        }
        if (delta1 > 0) {
            CurrencySettler.take(data.key.currency1, manager, data.sender, uint256(delta1), data.takeClaims);
            // send tokens back to harness
            data.key.currency1.transfer(Harness, uint256(delta1));
        }

        return abi.encode(delta);
    }
}
