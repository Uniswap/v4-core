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

contract TakeActionProps is ActionFuzzBase {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;
    using ProtocolFeeLibrary for uint16;

    Currency _takeCurrency;
    address _takeActor;

    uint256 _takeAmount;
    uint256 _takeActorBalanceBefore;
    uint256 _takeSingletonBalanceBefore;

    int256 _takeActorCurrencyDeltaBefore;

    function addTake(uint8 currency1I, uint256 amount) public {
        Currency c1 = Currencies[clampBetween(currency1I, 0, NUMBER_CURRENCIES - 1)];

        bytes memory takeParams = abi.encode(c1, address(actionsRouter), amount);

        bytes memory beforeTakeCbParam = _encodeHarnessCallback(ActionCallbacks.BEFORE_TAKE, takeParams);

        actions.push(Actions.HARNESS_CALLBACK);
        params.push(beforeTakeCbParam);

        actions.push(Actions.TAKE);
        params.push(takeParams);

        bytes memory afterTakeCbParam = _encodeHarnessCallback(ActionCallbacks.AFTER_TAKE, new bytes(0));
        actions.push(Actions.HARNESS_CALLBACK);
        params.push(afterTakeCbParam);
    }

    function _beforeTake(bytes memory preTakeParams) internal {
        (_takeCurrency, _takeActor, _takeAmount) = abi.decode(preTakeParams, (Currency, address, uint256));

        _takeActorBalanceBefore = _takeCurrency.balanceOf(_takeActor);
        _takeSingletonBalanceBefore = _takeCurrency.balanceOf(address(manager));
        _takeActorCurrencyDeltaBefore = manager.currencyDelta(_takeActor, _takeCurrency);

        // assert actor currency delta is less than or equal to the pool balance
        _verifyGlobalProperties(_takeActor, _takeCurrency);
    }

    function _afterTake() internal {
        uint256 actorBalanceAfter = _takeCurrency.balanceOf(_takeActor);
        uint256 singletonBalanceAfter = _takeCurrency.balanceOf(address(manager));

        int256 expectedDelta = _takeActorCurrencyDeltaBefore - int256(_takeAmount);
        int256 actualDelta = manager.currencyDelta(_takeActor, _takeCurrency);
        // UNI-TAKE-1
        assertEq(
            expectedDelta,
            actualDelta,
            "After executing take(), the user's currencyDelta should be the difference between their previous delta and the amount taken"
        );
        // UNI-TAKE-2
        assertEq(
            _takeActorBalanceBefore + _takeAmount,
            actorBalanceAfter,
            "After executing take(), the user's balance should increase by the amount taken."
        );
        // UNI-TAKE-3
        assertEq(
            _takeSingletonBalanceBefore - _takeAmount,
            singletonBalanceAfter,
            "After executing take(), the singleton's balance should decrease by the amount taken."
        );

        _verifyGlobalProperties(_takeActor, _takeCurrency);
        _addToActorsDebts(address(_takeActor), _takeCurrency, _takeAmount);
    }
}
