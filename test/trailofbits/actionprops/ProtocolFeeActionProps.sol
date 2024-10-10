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
import {IProtocolFeeController} from "src/interfaces/IProtocolFeeController.sol";
import {ProtocolFeeLibrary} from "src/libraries/ProtocolFeeLibrary.sol";

/// @notice This set of properties was written before protocol fee collection was modified to only work while the
// singleton is locked, addressing TOB-UNI4-3. To re-enable these properties, this contract needs to be refactored to only run fee collection
// while the singleton is locked.
contract ProtocolFeeActionProps is ActionFuzzBase {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;
    using ProtocolFeeLibrary for uint16;

    uint24 CurrentProtocolFee;

    function protocolFeeForPool(PoolKey memory) external view returns (uint24 protocolFee) {
        return CurrentProtocolFee;
    }

    /* Setting protocol fee */
    function _setNewProtocolFee(bytes memory setNewProtocolFeeParams) internal {
        (PoolKey memory poolKey, uint24 amount) = abi.decode(setNewProtocolFeeParams, (PoolKey, uint24));

        manager.setProtocolFee(poolKey, amount);
        CurrentProtocolFee = amount;
    }

    function addSetNewProtocolFee(uint8 poolIdx, uint24 amount) public {
        // ensure the protocol fee controller is set first
        if (address(manager.protocolFeeController()) != address(this)) {
            manager.setProtocolFeeController(IProtocolFeeController(address(this)));
        }
        PoolKey memory poolKey = _clampToValidPool(poolIdx);

        bytes memory setNewProtocolFeeParams = abi.encode(poolKey, amount);
        bytes memory setNewProtocolFeeCbParams =
            _encodeHarnessCallback(ActionCallbacks.SET_NEW_PROTOCOL_FEE, setNewProtocolFeeParams);

        actions.push(Actions.HARNESS_CALLBACK);
        params.push(setNewProtocolFeeCbParams);
    }

    /* Collecting protocol fees */

    function _collectProtocolFees(bytes memory collectProtocolFeesParams) internal {
        // we don't need a _before or _after since we're calling this from our harness, not ActionsRouter
        Currency currency = abi.decode(collectProtocolFeesParams, (Currency));
        uint256 feeToCollect = manager.protocolFeesAccrued(currency);

        try manager.collectProtocolFees(address(this), currency, feeToCollect) {}
        catch (bytes memory b) {
            emit LogBytes(b);
            // UNI-ACTION-6
            assertWithMsg(false, "collectProtocolFees must not revert on valid input");
        }

        _verifyGlobalProperties(address(actionsRouter), currency);
    }

    function addCollectProtocolFees(uint8 currencyIdx) public {
        Currency currency = Currencies[clampBetween(currencyIdx, 0, NUMBER_CURRENCIES - 1)];
        if (address(manager.protocolFeeController()) != address(this)) {
            manager.setProtocolFeeController(IProtocolFeeController(address(this)));
        }

        bytes memory collectProtocolFeesParams = abi.encode(currency);
        bytes memory collectProtocolFeesCbParams =
            _encodeHarnessCallback(ActionCallbacks.COLLECT_PROTOCOL_FEES, collectProtocolFeesParams);

        actions.push(Actions.HARNESS_CALLBACK);
        params.push(collectProtocolFeesCbParams);
    }
}
