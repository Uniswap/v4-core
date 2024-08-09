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

contract ClearActionProps is ActionFuzzBase {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;
    using ProtocolFeeLibrary for uint16;


    Currency _clearCurrency;
    uint256 _clearAmount;
    int256 _clearActorCurrencyDeltaBefore;

    function addClear(uint8 curIdx, uint256 amount) public {
        Currency currency = Currencies[clampBetween(curIdx, 0, NUMBER_CURRENCIES-1)];

        bytes memory clearParams = abi.encode(currency, amount, false, "");
        bytes memory beforeClearCbParams = _encodeHarnessCallback(ActionCallbacks.BEFORE_CLEAR, clearParams);

        actions.push(Actions.HARNESS_CALLBACK);
        params.push(beforeClearCbParams);

        
        actions.push(Actions.CLEAR);
        params.push(clearParams);
        bytes memory afterClearCbParam = _encodeHarnessCallback(ActionCallbacks.AFTER_CLEAR, new bytes(0));
        actions.push(Actions.HARNESS_CALLBACK);
        params.push(afterClearCbParam);
    }


    function _beforeClear(bytes memory preClearParams) internal {
        (_clearCurrency, _clearAmount,,) = abi.decode(preClearParams, (Currency, uint256, bool, string));
        _clearActorCurrencyDeltaBefore = manager.currencyDelta(address(actionsRouter), _clearCurrency);

        _verifyGlobalProperties(address(actionsRouter),_clearCurrency);
    }

    function _afterClear() internal {
        int256 actorCurrencyDeltaAfter = manager.currencyDelta(address(actionsRouter), _clearCurrency);

        int256 actorCurrencyDelta = _clearActorCurrencyDeltaBefore - actorCurrencyDeltaAfter;
        // UNI-SETTLE-12
        assertGte(actorCurrencyDelta, 0, "After a clear, the actor's currency delta should go down or be equal to zero.");
        // UNI-SETTLE-13
        assertEq(uint256(actorCurrencyDelta), _clearAmount, "After a clear, the actor's currency delta should be equal to the amount cleared.");


        _addToActorsDebts(address(actionsRouter), _clearCurrency, _clearAmount);
        _verifyGlobalProperties(address(actionsRouter),_clearCurrency);
    }      


}

