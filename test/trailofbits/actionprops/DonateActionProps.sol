// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ActionFuzzBase, ActionCallbacks} from "test/trailofbits/ActionFuzzBase.sol";
import {PoolId, PoolIdLibrary} from "src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "src/types/Currency.sol";
import {PoolKey} from "src/types/PoolKey.sol";
import {Actions} from "src/test/ActionsRouter.sol";
import {StateLibrary} from "src/libraries/StateLibrary.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "src/types/BalanceDelta.sol";
import {IPoolManager} from "src/interfaces/IPoolManager.sol";
import {FixedPoint128} from "src/libraries/FixedPoint128.sol";
import {TransientStateLibrary} from "src/libraries/TransientStateLibrary.sol";
import {FullMath} from "src/libraries/FullMath.sol";

contract DonateActionProps is ActionFuzzBase {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;
    using TransientStateLibrary for IPoolManager;

    PoolKey _donatePoolKey;
    uint256 _donateAmount0;
    uint256 _donateAmount1;
    uint256 _feeGrowthGlobal0X128Before;
    uint256 _feeGrowthGlobal1X128Before;

    function addDonate(uint8 poolIdx, uint256 amount0, uint256 amount1) public {
        PoolKey memory pk = _clampToValidPool(poolIdx);
        bytes memory donateParam = abi.encode(pk, amount0, amount1);

        actions.push(Actions.HARNESS_CALLBACK);
        bytes memory beforeDonateCbParam = _encodeHarnessCallback(ActionCallbacks.BEFORE_DONATE, donateParam);
        params.push(beforeDonateCbParam);

        actions.push(Actions.DONATE);
        params.push(donateParam);

        actions.push(Actions.HARNESS_CALLBACK);
        bytes memory afterDonateCbParam = _encodeHarnessCallback(ActionCallbacks.AFTER_DONATE, new bytes(0));
        params.push(afterDonateCbParam);
    }

    function _beforeDonate(bytes memory preDonateParam) internal {
        (_donatePoolKey, _donateAmount0, _donateAmount1) = abi.decode(preDonateParam, (PoolKey, uint256, uint256));

        (_feeGrowthGlobal0X128Before, _feeGrowthGlobal1X128Before) = manager.getFeeGrowthGlobals(_donatePoolKey.toId());
        _verifyGlobalProperties(address(actionsRouter), _donatePoolKey.currency0);
        _verifyGlobalProperties(address(actionsRouter), _donatePoolKey.currency1);
    }

    function _afterDonate(BalanceDelta delta) internal {
        // UNI-DONATE-6
        assertLte(delta.amount0(), 0, "A donate() call must not return a positive BalanceDelta for currency0");
        // UNI-DONATE-7
        assertLte(delta.amount1(), 0, "A donate() call must not return a positive BalanceDelta for currency1");

        // UNI-DONATE-8
        assertEq(_donateAmount0, uint128(-delta.amount0()), "The donate() call BalanceDelta must match the amount donated for amount0");
        // UNI-DONATE-9
        assertEq(_donateAmount1, uint128(-delta.amount1()), "The donate() call BalanceDelta must match the amount donated for amount1");

        PoolId donatePoolId = _donatePoolKey.toId();
        uint128 liquidity = manager.getLiquidity(donatePoolId);
        
        uint256 feeGrowthDelta0X128 = FullMath.mulDiv(uint256(uint128(-delta.amount0())), FixedPoint128.Q128, liquidity);
        uint256 feeGrowthDelta1X128 = FullMath.mulDiv(uint256(uint128(-delta.amount1())), FixedPoint128.Q128, liquidity);

        uint256 feeGrowth0X128Expected = _calculateExpectedFeeGrowth(feeGrowthDelta0X128, _feeGrowthGlobal0X128Before);
        uint256 feeGrowth1X128Expected = _calculateExpectedFeeGrowth(feeGrowthDelta1X128, _feeGrowthGlobal1X128Before);
        

        (uint256 feeGrowth0AfterX128, uint256 feeGrowth1AfterX128) = manager.getFeeGrowthGlobals(donatePoolId);
        if (liquidity > 0 ) {
            if(_donateAmount0 > 0) {
                // UNI-DONATE-1
                assertEq(feeGrowth0X128Expected, feeGrowth0AfterX128 , "After a donation with a non-zero amount0, the pool's feeGrowthGlobal0X128 be equal to the amount0 BalanceDelta, accounting for overflows.");
            } else {
                // UNI-DONATE-3
                assertEq(_feeGrowthGlobal0X128Before, feeGrowth0AfterX128, "After a donation with a zero amount0, the pool's feeGrowthGlobal0X128 should not change.");
            }

            if(_donateAmount1 > 0) {
                // UNI-DONATE-2
                assertEq(feeGrowth1X128Expected, feeGrowth1AfterX128, "After a donation with a non-zero amount1, the pool's feeGrowthGlobal0X128 be equal to the amount1 BalanceDelta, accounting for overflows.");
            } else {
                // UNI-DONATE-4
                assertEq(_feeGrowthGlobal1X128Before, feeGrowth1AfterX128, "After a donation with a zero amount1, the pool's feeGrowthGlobal1X128 should not change.");
            }
        } else {
            // fee growth should not have changed
            // UNI-DONATE-5
            assertWithMsg(false, "Donating to a pool with zero liquidity should result in a revert.");
        }

        /* Update virtual pool reserves  */

        _updateCurrencyDelta(address(actionsRouter), _donatePoolKey.currency0, delta.amount0());
        _updateCurrencyDelta(address(actionsRouter), _donatePoolKey.currency1, delta.amount1());

        SingletonLPFees[_donatePoolKey.currency0] = _deltaAdd(SingletonLPFees[_donatePoolKey.currency0], int256(_donateAmount0));
        SingletonLPFees[_donatePoolKey.currency1] = _deltaAdd(SingletonLPFees[_donatePoolKey.currency1], int256(_donateAmount1));


        _verifyGlobalProperties(address(actionsRouter), _donatePoolKey.currency0);
        _verifyGlobalProperties(address(actionsRouter), _donatePoolKey.currency1);
    }
}