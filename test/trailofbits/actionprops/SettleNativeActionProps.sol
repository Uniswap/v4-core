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

contract SettleNativeActionProps is ActionFuzzBase {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;
    using ProtocolFeeLibrary for uint16;


    address _settleNativeActor;
    uint256 _settleNativeAmount;


    function addSettleNative(uint256 amount) public {

        bytes memory beforeSettleCbParams = _encodeHarnessCallback(ActionCallbacks.BEFORE_SETTLE_NATIVE, abi.encode(address(actionsRouter), amount));

        actions.push(Actions.HARNESS_CALLBACK);
        params.push(beforeSettleCbParams);

        actions.push(Actions.SETTLE_NATIVE);
        params.push(abi.encode(amount));

        bytes memory afterSettleCbParam = _encodeHarnessCallback(ActionCallbacks.AFTER_SETTLE_NATIVE, new bytes(0));
        actions.push(Actions.HARNESS_CALLBACK);
        params.push(afterSettleCbParam);
    }


    function _beforeSettleNative(bytes memory preSettleParams) internal {
        (_settleNativeActor, _settleNativeAmount) = abi.decode(preSettleParams, (address, uint256));
        // transfer currency to actionsRouter
        payable(address(actionsRouter)).transfer(_settleNativeAmount);

        _verifyGlobalProperties(_settleNativeActor, CurrencyLibrary.ADDRESS_ZERO);
    }

    function _afterSettleNative(uint256 paid) internal {
        _verifyGlobalProperties(_settleNativeActor, CurrencyLibrary.ADDRESS_ZERO);
        _addToActorsCredits(_settleNativeActor, CurrencyLibrary.ADDRESS_ZERO, paid);
        

    }      


}

