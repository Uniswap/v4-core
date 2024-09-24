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

contract SettleActionProps is ActionFuzzBase {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;
    using ProtocolFeeLibrary for uint16;

    address _settleActor;
    Currency _settleReserveCurrency;
    int256 _currencyDeltaBefore;

    function addSettle() public {
        bytes memory beforeSettleCbParams =
            _encodeHarnessCallback(ActionCallbacks.BEFORE_SETTLE, abi.encode(address(actionsRouter)));

        actions.push(Actions.HARNESS_CALLBACK);
        params.push(beforeSettleCbParams);

        actions.push(Actions.SETTLE);
        params.push(new bytes(0));

        bytes memory afterSettleCbParam = _encodeHarnessCallback(ActionCallbacks.AFTER_SETTLE, new bytes(0));
        actions.push(Actions.HARNESS_CALLBACK);
        params.push(afterSettleCbParam);
    }

    function addSettleFor(address addr) public {
        bytes memory settleForParams = abi.encode(addr);

        bytes memory beforeSettleCbParams = _encodeHarnessCallback(ActionCallbacks.BEFORE_SETTLE, settleForParams);

        actions.push(Actions.HARNESS_CALLBACK);
        params.push(beforeSettleCbParams);

        actions.push(Actions.SETTLE_FOR);
        params.push(settleForParams);

        bytes memory afterSettleCbParam = _encodeHarnessCallback(ActionCallbacks.AFTER_SETTLE, new bytes(0));
        actions.push(Actions.HARNESS_CALLBACK);
        params.push(afterSettleCbParam);
    }

    function _beforeSettle(bytes memory preSettleParams) internal {
        _settleActor = abi.decode(preSettleParams, (address));
        _settleReserveCurrency = manager.getSyncedCurrency();

        // The only reason we keep track of remittance currency separately like this is to validate our assumptions about how
        // transient storage works during runtime.
        emit LogAddress("synced currency", address(Currency.unwrap(_settleReserveCurrency)));
        emit LogAddress("Remittance currency", address(Currency.unwrap(RemittanceCurrency)));

        _currencyDeltaBefore = manager.currencyDelta(_settleActor, _settleReserveCurrency);
        _verifyGlobalProperties(_settleActor, _settleReserveCurrency);
    }

    function _afterSettle(uint256 paid) internal {
        int256 currencyDeltaAfterSettle = manager.currencyDelta(_settleActor, _settleReserveCurrency);

        int256 currencyDeltaDifference = currencyDeltaAfterSettle - _currencyDeltaBefore;

        // UNI-SETTLE-1
        assertGte(
            currencyDeltaDifference,
            0,
            "The user must not be owed more tokens after a settle than they were owed before a settle."
        );
        // UNI-SETTLE-2
        assertEq(
            currencyDeltaDifference,
            int256(paid),
            "The amount paid during a settle must be equal to the difference in the user's currency deltas before and after the settle call."
        );
        // UNI-SETTLE-3
        assertEq(
            int256(paid),
            RemittanceAmount,
            "The amount paid during a settle must be equal to the amount of remittances paid to the singleton."
        );

        _addToActorsCredits(_settleActor, _settleReserveCurrency, paid);
        _verifyGlobalProperties(_settleActor, _settleReserveCurrency);
        RemittanceCurrency = CurrencyLibrary.ADDRESS_ZERO;
    }
}
