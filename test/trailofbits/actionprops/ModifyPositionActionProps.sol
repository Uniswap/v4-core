// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ActionFuzzBase, ActionCallbacks} from "test/trailofbits/ActionFuzzBase.sol";
import {V4StateMachine} from "test/trailofbits/V4StateMachine.sol";
import {PoolId, PoolIdLibrary} from "src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "src/types/Currency.sol";
import {PoolKey} from "src/types/PoolKey.sol";
import {Actions} from "src/test/ActionsRouter.sol";
import {IHooks} from "src/interfaces/IHooks.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "src/types/BalanceDelta.sol";
import {TransientStateLibrary} from "src/libraries/TransientStateLibrary.sol";
import {StateLibrary} from "src/libraries/StateLibrary.sol";
import {IPoolManager} from "src/interfaces/IPoolManager.sol";
import {Position} from "src/libraries/Position.sol";
import {FixedPoint128} from "src/libraries/FixedPoint128.sol";
import {FullMath} from "src/libraries/FullMath.sol";

contract ModifyPositionActionProps is ActionFuzzBase {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using TransientStateLibrary for IPoolManager;
    using StateLibrary for IPoolManager;

    struct ExistingPosition {
        Position.Info positionInfo;
    }

    PoolKey _modifyPoolKey;
    bytes32 _modifySalt;
    int128 _modifyLiqDelta;
    int24 _modifyLowTick;
    int24 _modifyHighTick;
    uint256 _modifyFeeGrowthGlobal0;
    uint256 _modifyFeeGrowthGlobal1;

    uint128 _modifyPositionLiquidityBefore;
    uint256 _modifyFeeGrowthInside0Before;
    uint256 _modifyFeeGrowthInside1Before;

    uint256 _modifyFeesExpectedDelta0X128;
    uint256 _modifyFeesExpectedDelta1X128;
    uint128 _modifyLiquidityExpected;

    Position.Info _modifyPositionInfoBefore;



    function addModifyPosition(uint8 poolIdx, int24 lowTick, int24 highTick, int128 liqDelta, uint256 salt) public {
        // potential props: StateLibrary.getTickLiquidity
        // StateLibrary.getLiquidity
        // getPositionLiquidity


        // getModifyPositionBefore
        // snapshot liquidity of position
        // snapshot liquidity of pool
        // snapshot fees
        // snapshot price
        // snapshot tick



        // getModifyPositionAfter
        
        PoolKey memory pk = _clampToValidPool(poolIdx);
        
        (lowTick, highTick) = _clampToUsableTicks(lowTick, highTick, pk);
        bytes memory modifyParam = abi.encode(pk, lowTick, highTick, liqDelta, bytes32(salt));

        bytes memory beforeModifyCbParam = _encodeHarnessCallback(ActionCallbacks.BEFORE_MODIFY_POSITION, modifyParam);
        actions.push(Actions.HARNESS_CALLBACK);
        params.push(beforeModifyCbParam);

        actions.push(Actions.MODIFY_POSITION);
        params.push(modifyParam);

        bytes memory afterModifyCbParam = _encodeHarnessCallback(ActionCallbacks.AFTER_MODIFY_POSITION, new bytes(0));
        actions.push(Actions.HARNESS_CALLBACK);
        params.push(afterModifyCbParam);
    }

    function _beforeModifyPosition(bytes memory preModifyParams) internal {
        (_modifyPoolKey, _modifyLowTick, _modifyHighTick,_modifyLiqDelta ,_modifySalt ) =
            abi.decode(preModifyParams, (PoolKey, int24, int24, int128, bytes32));

        (_modifyFeeGrowthGlobal0, _modifyFeeGrowthGlobal1) = manager.getFeeGrowthGlobals(_modifyPoolKey.toId());

        (_modifyPositionLiquidityBefore, _modifyFeeGrowthInside0Before, _modifyFeeGrowthInside1Before) = manager.getPositionInfo(
            _modifyPoolKey.toId(),
            _modifySalt
        );
        _modifyPositionInfoBefore = manager.getPosition(_modifyPoolKey.toId(), address(actionsRouter), _modifyLowTick, _modifyHighTick, _modifySalt);
        (_modifyFeesExpectedDelta0X128, _modifyFeesExpectedDelta1X128, _modifyLiquidityExpected) = _calculateExpectedFeeDelta(_modifyPoolKey.toId(), _modifyLiqDelta, _modifyLowTick, _modifyHighTick, address(actionsRouter), _modifySalt);

        _verifyGlobalProperties(address(actionsRouter), _modifyPoolKey.currency0);
        _verifyGlobalProperties(address(actionsRouter), _modifyPoolKey.currency1);
        _verifyStateLibraryGetterEquivalence();
    }

    function _afterModifyPosition(BalanceDelta callerDelta, BalanceDelta feesAccrued) internal {
        emit LogInt256("modify liquidity callerDelta amount0", callerDelta.amount0());
        emit LogInt256("modify liquidity callerDelta amount1", callerDelta.amount1());
        emit LogInt256("modify liquidity feesAccrued amount0", feesAccrued.amount0());
        emit LogInt256("modify liquidity feesAccrued amount1", feesAccrued.amount1());

        // UNI-MODLIQ-4
        assertGte(feesAccrued.amount0(), 0, "The amount0 of fees accrued from modifyPosition() must be non-negative");
        // UNI-MODLIQ-5
        assertGte(feesAccrued.amount1(), 0, "The amount1 of fees accrued from modifyPosition() must be non-negative");
        
        // UNI-MODLIQ-8
        assertGte(PoolLiquidities[_modifyPoolKey.toId()].amount0, callerDelta.amount0(), "The pool must have enough currency0 to return the LP's liquidity balance plus fees.");
        // UNI-MODLIQ-9
        assertGte(PoolLiquidities[_modifyPoolKey.toId()].amount1, callerDelta.amount1(), "The pool must have enough currency1 to return the LP's liquidity balance plus fees.");

        // assert fees == fees expected
        assertEq(uint128(feesAccrued.amount0()), _modifyFeesExpectedDelta0X128, "The amount0 of fees accrued from modifyPosition() must match the expected fee.");
        assertEq(uint128(feesAccrued.amount1()), _modifyFeesExpectedDelta1X128, "The amount1 of fees accrued from modifyPosition() must match the expected fee.");

        // UNI-MODLIQ-6
        assertGte(SingletonLPFees[_modifyPoolKey.currency0],  uint128(feesAccrued.amount0()), "The singleton must be able to credit the user for the amount of feeGrowth they are owed (amount0)");
        // UNI-MODLIQ-7
        assertGte(SingletonLPFees[_modifyPoolKey.currency1],  uint128(feesAccrued.amount1()), "The singleton must be able to credit the user for the amount of feeGrowth they are owed (amount1)");
        

        if(callerDelta.amount0() > 0) {
            // UNI-MODLIQ-10
            assertGte(SingletonLiquidity[_modifyPoolKey.currency0], uint256(uint128(callerDelta.amount0())) - uint256(uint128(feesAccrued.amount0())), "The singleton must have enough currency0 to return the LP's liquidity balance");
        }
        if(callerDelta.amount1() > 0){
            // UNI-MOQLIQ-11
            assertGte(SingletonLiquidity[_modifyPoolKey.currency1], uint256(uint128(callerDelta.amount1())) - uint256(uint128(feesAccrued.amount1())), "The singleton must have enough currency1 to return the LP's liquidity balance");
        }

        int256 principalDelta0 = callerDelta.amount0() - feesAccrued.amount0();
        int256 principalDelta1 = callerDelta.amount1() - feesAccrued.amount1();


        /* Update virtual pool reserves  */
        PoolLiquidities[_modifyPoolKey.toId()].amount0 -= principalDelta0;
        PoolLiquidities[_modifyPoolKey.toId()].amount1 -= principalDelta1;

        emit LogInt256("Pool Liquidity amount0 updated", PoolLiquidities[_modifyPoolKey.toId()].amount0);
        emit LogInt256("Pool Liquidity amount1 updated", PoolLiquidities[_modifyPoolKey.toId()].amount1);

        // Update singleton liquidity
        uint256 newSingletonLiq0 = _deltaAdd(SingletonLiquidity[_modifyPoolKey.currency0], -(principalDelta0));
        emit LogUint256("Singleton now has this much liquidity for amount0:", newSingletonLiq0);
        uint256 newSingletonLiq1 = _deltaAdd(SingletonLiquidity[_modifyPoolKey.currency1], -(principalDelta1));
        emit LogUint256("Singleton now has this much liquidity for amount1:", newSingletonLiq1);

        SingletonLiquidity[_modifyPoolKey.currency0] = newSingletonLiq0;
        SingletonLiquidity[_modifyPoolKey.currency1] = newSingletonLiq1;

        SingletonLPFees[_modifyPoolKey.currency0] -= uint128(feesAccrued.amount0());
        SingletonLPFees[_modifyPoolKey.currency1] -= uint128(feesAccrued.amount1());

        // do not bother using _addToActorsCredits/_addToActorsDebts since BalanceDelta is already int128
        _updateCurrencyDelta(address(actionsRouter), _modifyPoolKey.currency0, callerDelta.amount0() );
        _updateCurrencyDelta(address(actionsRouter), _modifyPoolKey.currency1, callerDelta.amount1() );

        // update our positions lookup
        _updatePoolPositions();

        _verifyGlobalProperties(address(actionsRouter), _modifyPoolKey.currency0);
        _verifyGlobalProperties(address(actionsRouter), _modifyPoolKey.currency1);
    }

    function _verifyStateLibraryGetterEquivalence() internal {
        Position.Info memory positionInfo = manager.getPosition(_modifyPoolKey.toId(), address(actionsRouter), _modifyLowTick, _modifyHighTick, _modifySalt);

        bytes32 positionId = keccak256(abi.encodePacked(address(actionsRouter), _modifyLowTick, _modifyHighTick, _modifySalt));
        (uint128 positionLiq, uint256 positionFeeGrowth0, uint256 positionFeeGrowth1) = manager.getPositionInfo(
            _modifyPoolKey.toId(),
            positionId
        );
        // UNI-MODLIQ-1
        assertEq(positionInfo.liquidity, positionLiq, "For a specific position, getPositionInfo must return the same liquidity as getPosition");
        // UNI-MODLIQ-2
        assertEq(positionInfo.feeGrowthInside0LastX128, positionFeeGrowth0, "For a specific position, getPositionInfo must return the same feeGrowthInside0 as getPosition");
        // UNI-MODLIQ-3
        assertEq(positionInfo.feeGrowthInside1LastX128, positionFeeGrowth1, "For a specific position, getPositionInfo must return the same feeGrowthInside1 as getPosition");
    }

    function _calculateExpectedFeeDelta(PoolId poolId, int128 liqDelta, int24 lowTick, int24 highTick, address owner, bytes32 salt) internal view returns (uint256, uint256,uint128) {
        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = manager.getFeeGrowthInside(poolId, lowTick, highTick);
        Position.Info memory positionInfo = manager.getPosition(poolId, owner, lowTick, highTick, salt);

        if (liqDelta == 0 && positionInfo.liquidity == 0) {
            // this isn't the place for checking properties
            return (0,0,0);
        }
        
        // doing this outside yul will let us indirectly check their LiquidityMath.addDelta
        uint128 liquidityExpected;
        if(liqDelta > 0) {
            liquidityExpected = positionInfo.liquidity + uint128(liqDelta);
        } else {
            liquidityExpected = positionInfo.liquidity - uint128(-liqDelta);
        }

        uint256 feesOwed0;
        uint256 feesOwed1;

        unchecked {
            feesOwed0 =
                FullMath.mulDiv(feeGrowthInside0X128 - positionInfo.feeGrowthInside0LastX128, positionInfo.liquidity, FixedPoint128.Q128);
            feesOwed1 =
                FullMath.mulDiv(feeGrowthInside1X128 - positionInfo.feeGrowthInside1LastX128, positionInfo.liquidity, FixedPoint128.Q128);
        }

        return (feesOwed0, feesOwed1, liquidityExpected);
    }

    function _updatePoolPositions() internal {
        bytes32 positionId = keccak256(abi.encodePacked(address(actionsRouter), _modifyLowTick, _modifyHighTick, _modifySalt));
        (uint128 positionLiq, , ) = manager.getPositionInfo(
            _modifyPoolKey.toId(),
            positionId
        );

        bytes32 positionInfoLookup = keccak256(abi.encodePacked(_modifyPoolKey.toId(), positionId));
        int index = PositionInfoIndex[positionInfoLookup];
        if(index == 0) {
            // position does not exist in list
            V4StateMachine.PositionInfo memory newPosition = V4StateMachine.PositionInfo(0, _modifyLowTick, _modifyHighTick);
            index = int(PoolPositions[_modifyPoolKey.toId()].length);
            int newPositionIdx = index;
            if (newPositionIdx == 0) {
                newPositionIdx = -1;
            }
            PoolPositions[_modifyPoolKey.toId()].push(newPosition);
            PositionInfoIndex[positionInfoLookup] = newPositionIdx;

        } else if (index == -1) {
            // we use -1 for the position that actually lives at index 0
            index = 0;
        }
        emit LogInt256("setting liq for position idx", index);
        emit LogUint256("to liquidity ", positionLiq);

        PoolPositions[_modifyPoolKey.toId()][uint(index)].liquidity = positionLiq;
    }
}