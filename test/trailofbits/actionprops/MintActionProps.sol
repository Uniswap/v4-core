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

contract MintActionProps is ActionFuzzBase {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;
    using ProtocolFeeLibrary for uint16;


    address _mintRecipient;
    Currency _mintReserveCurrency;
    uint256 _mintAmount;
    int256 _mintSenderCurrencyDeltaBefore;
    uint256 _mintRecipientBalanceBefore;


    function addMint(address recipient, uint8 curIdx, uint256 amount) public {
        Currency currency = Currencies[clampBetween(curIdx, 0, NUMBER_CURRENCIES-1)];

        bytes memory mintParams = abi.encode(recipient, currency, amount);
        bytes memory beforeMintCbParams = _encodeHarnessCallback(ActionCallbacks.BEFORE_MINT, mintParams);

        actions.push(Actions.HARNESS_CALLBACK);
        params.push(beforeMintCbParams);

        actions.push(Actions.MINT);
        params.push(mintParams);

        bytes memory afterMintCbParam = _encodeHarnessCallback(ActionCallbacks.AFTER_MINT, new bytes(0));
        actions.push(Actions.HARNESS_CALLBACK);
        params.push(afterMintCbParam);
    }



    function _beforeMint(bytes memory preMintParams) internal {
        (_mintRecipient, _mintReserveCurrency, _mintAmount) = abi.decode(preMintParams, (address, Currency, uint256));
        _mintSenderCurrencyDeltaBefore = manager.currencyDelta(address(actionsRouter), _mintReserveCurrency);
        _mintRecipientBalanceBefore = manager.balanceOf(_mintRecipient, _mintReserveCurrency.toId());
        _verifyGlobalProperties(address(actionsRouter), _mintReserveCurrency);
        emit LogUint256("mint amount", _mintAmount);
        emit LogInt256("mint sender currency delta", _mintSenderCurrencyDeltaBefore);
    }

    function _afterMint() internal {
        int256 actorCurrencyDeltaAfter = manager.currencyDelta(address(actionsRouter), _mintReserveCurrency);
        emit LogInt256("mint sender currency delta after", actorCurrencyDeltaAfter);
        int256 expectedDeltaMint = _mintSenderCurrencyDeltaBefore - actorCurrencyDeltaAfter;
        // UNI-SETTLE-8
        assertGte(expectedDeltaMint, 0, "After a mint, the sender's currency delta should decrease to reflect increased debt.");
        // UNI-SETTLE-9
        assertEq(uint256(expectedDeltaMint), _mintAmount, "After a mint, the difference between the sender's previous and new currency delta should match the mint amount");

        uint256 newRecipientBalance = manager.balanceOf(_mintRecipient, _mintReserveCurrency.toId());  
        //UNI-SETTLE-10
        assertGte(newRecipientBalance, _mintRecipientBalanceBefore, "After a mint, the recipient's ERC6909 balance should increase");

        uint256 recipientDelta = newRecipientBalance - _mintRecipientBalanceBefore;
        // UNI-SETTLE-11
        assertEq(recipientDelta, _mintAmount, "After a mint, the recipient's ERC6909 balance should increase by the mint amount");

        _addToActorsDebts(address(actionsRouter), _mintReserveCurrency, _mintAmount);
        _verifyGlobalProperties(address(actionsRouter), _mintReserveCurrency);

    }      


}