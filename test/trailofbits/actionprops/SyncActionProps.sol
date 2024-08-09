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

contract SyncActionProps is ActionFuzzBase {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;
    using ProtocolFeeLibrary for uint16;

    Currency _syncCurrency;

    function addSync(uint8 curIdx) public {
        Currency currency = Currencies[clampBetween(curIdx, 0, NUMBER_CURRENCIES-1)];


        bytes memory syncParams = abi.encode(currency);
        bytes memory beforeSyncCbParams = _encodeHarnessCallback(ActionCallbacks.BEFORE_SYNC, syncParams);

        actions.push(Actions.HARNESS_CALLBACK);
        params.push(beforeSyncCbParams);

        actions.push(Actions.SYNC);
        params.push(syncParams);

        bytes memory afterSyncCbParam = _encodeHarnessCallback(ActionCallbacks.AFTER_SYNC, new bytes(0));
        actions.push(Actions.HARNESS_CALLBACK);
        params.push(afterSyncCbParam);
    }

    function _beforeSync(bytes memory preSyncParams) internal {
        _syncCurrency = abi.decode(preSyncParams, (Currency));
    }

    function _afterSync() internal {
        if(!(_syncCurrency == CurrencyLibrary.NATIVE)){
            RemittanceCurrency = _syncCurrency;
            RemittanceAmount = 0;
        }

    }      


}

