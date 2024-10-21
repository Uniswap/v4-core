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

contract BurnActionProps is ActionFuzzBase {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;
    using ProtocolFeeLibrary for uint16;

    address _burnFromActor;
    Currency _burnReserveCurrency;
    uint256 _burnAmount;
    int256 _burnSenderCurrencyDeltaBefore;
    uint256 _burnFromActorBalanceBefore;

    function addBurn(address from, uint8 curIdx, uint256 amount) public {
        Currency currency = Currencies[clampBetween(curIdx, 0, NUMBER_CURRENCIES - 1)];

        bytes memory burnParams = abi.encode(from, currency, amount);
        bytes memory beforeBurnCbParams = _encodeHarnessCallback(ActionCallbacks.BEFORE_BURN, burnParams);

        actions.push(Actions.HARNESS_CALLBACK);
        params.push(beforeBurnCbParams);

        actions.push(Actions.BURN);
        params.push(burnParams);

        bytes memory afterBurnCbParam = _encodeHarnessCallback(ActionCallbacks.AFTER_BURN, new bytes(0));
        actions.push(Actions.HARNESS_CALLBACK);
        params.push(afterBurnCbParam);
    }

    function _beforeBurn(bytes memory preBurnParams) internal {
        (_burnFromActor, _burnReserveCurrency, _burnAmount) = abi.decode(preBurnParams, (address, Currency, uint256));
        _burnSenderCurrencyDeltaBefore = manager.currencyDelta(address(actionsRouter), _burnReserveCurrency);
        _burnFromActorBalanceBefore = manager.balanceOf(_burnFromActor, _burnReserveCurrency.toId());
        emit LogUint256("burn from actor balance", _burnFromActorBalanceBefore);
        _verifyGlobalProperties(address(actionsRouter), _burnReserveCurrency);
    }

    function _afterBurn() internal {
        int256 senderNewCurrencyDelta = manager.currencyDelta(address(actionsRouter), _burnReserveCurrency);
        int256 expectedBurnAmount = senderNewCurrencyDelta - _burnSenderCurrencyDeltaBefore;

        // UNI-SETTLE-4
        assertGte(
            expectedBurnAmount,
            0,
            "After a burn, the sender's currency delta should increase to reflect the decreased debt."
        );
        // UNI-SETTLE-5 (strong version of 4)
        assertEq(
            uint256(expectedBurnAmount),
            _burnAmount,
            "After a burn, the difference between the sender's previous and new currency delta should equal the burn amount"
        );

        uint256 newRecipientBalance = manager.balanceOf(_burnFromActor, _burnReserveCurrency.toId());
        // UNI-SETTLE-6
        assertLte(
            newRecipientBalance,
            _burnFromActorBalanceBefore,
            "After a burn, the from actor's balance should decrease to reflect the burned amount"
        );

        // note: it would be really nice to abstract away some of this overflow checking relationship to reduce the number of meaningless properties.
        // property math?
        emit LogUint256("new recipient balance", newRecipientBalance);
        uint256 fromActorDelta = _burnFromActorBalanceBefore - newRecipientBalance;
        // UNI-SETTLE-7
        assertEq(
            fromActorDelta,
            _burnAmount,
            "After a burn, the difference between the from actor's previous and new balance should equal the burn amount"
        );

        _addToActorsCredits(address(actionsRouter), _burnReserveCurrency, _burnAmount);
        _verifyGlobalProperties(address(actionsRouter), _burnReserveCurrency);
    }
}
