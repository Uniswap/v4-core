// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IHooks} from "src/interfaces/IHooks.sol";
import {IPoolManager} from "src/interfaces/IPoolManager.sol";
import {Hooks} from "src/libraries/Hooks.sol";
import {TickMath} from "src/libraries/TickMath.sol";
import {Deployers} from "test/utils/Deployers.sol";
import {StateLibrary} from "src/libraries/StateLibrary.sol";
import {TransientStateLibrary} from "src/libraries/TransientStateLibrary.sol";
import {PoolId, PoolIdLibrary} from "src/types/PoolId.sol";
import {PoolKey} from "src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "src/types/Currency.sol";
import {PropertiesAsserts} from "./PropertiesHelper.sol";
import {IProtocolFeeController} from "src/interfaces/IProtocolFeeController.sol";
import {Actions} from "../../src/test/ActionsRouter.sol";
import {IActionsHarness} from "./IActionsHarness.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "src/types/BalanceDelta.sol";
import {ActionFuzzBase, ActionCallbacks} from "./ActionFuzzBase.sol";



import {DonateActionProps} from "./actionprops/DonateActionProps.sol";
import {InitializeActionProps} from "./actionprops/InitializeActionProps.sol";
import {ModifyPositionActionProps} from "./actionprops/ModifyPositionActionProps.sol";
import {SwapActionProps} from "./actionprops/SwapActionProps.sol";
import {TakeActionProps} from "./actionprops/TakeActionProps.sol";
import {SettleActionProps} from "./actionprops/SettleActionProps.sol";
import {SettleNativeActionProps} from "./actionprops/SettleNativeActionProps.sol";
import {MintActionProps} from "./actionprops/MintActionProps.sol";
import {BurnActionProps} from "./actionprops/BurnActionProps.sol";
import {SyncActionProps} from "./actionprops/SyncActionProps.sol";
import {ClearActionProps} from "./actionprops/ClearActionProps.sol";
import {ProtocolFeeActionProps} from "./actionprops/ProtocolFeeActionProps.sol";

contract ActionFuzzEntrypoint is 
    ActionFuzzBase, 
    IActionsHarness, 
    DonateActionProps, 
    InitializeActionProps, 
    ModifyPositionActionProps,
    SwapActionProps,
    TakeActionProps,
    SettleActionProps,
    SettleNativeActionProps,
    MintActionProps,
    BurnActionProps,
    SyncActionProps,
    ClearActionProps {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using TransientStateLibrary for IPoolManager;

    // configure harness in ActionFuzzBase.sol
    constructor() payable { }

    function routerCallback(bytes memory data, bytes memory lastReturnData) external override {
        (ActionCallbacks cbType, bytes memory cbData) = abi.decode(data, (ActionCallbacks, bytes));

        if( cbType == ActionCallbacks.BEFORE_DONATE) {
            emit LogString("before donate");
            _beforeDonate(cbData);
        } else if (cbType == ActionCallbacks.AFTER_DONATE) {
            emit LogString("after donate");
            BalanceDelta bd = abi.decode(lastReturnData, (BalanceDelta));
            _afterDonate(bd);
        } else if (cbType == ActionCallbacks.BEFORE_SWAP) {
            emit LogString("before swap");
            _beforeSwap(cbData);
        } else if (cbType == ActionCallbacks.AFTER_SWAP) {
            emit LogString("after swap");
            _afterSwap(abi.decode(lastReturnData, (BalanceDelta)));
        } else if (cbType == ActionCallbacks.BEFORE_MODIFY_POSITION) {
            emit LogString("before modify position");
            _beforeModifyPosition(cbData);
        } else if (cbType == ActionCallbacks.AFTER_MODIFY_POSITION) {
            emit LogString("after modify position");
            (BalanceDelta b1, BalanceDelta b2) = abi.decode(lastReturnData, (BalanceDelta,BalanceDelta));
            _afterModifyPosition(b1, b2);
        } else if (cbType == ActionCallbacks.BEFORE_TAKE) {
            emit LogString("before take");
            _beforeTake(cbData);
        } else if (cbType == ActionCallbacks.AFTER_TAKE) {
            emit LogString("after take");
            _afterTake();
        } else if (cbType == ActionCallbacks.BEFORE_SETTLE) {
            emit LogString("before settle");
            _beforeSettle(cbData);
        } else if (cbType == ActionCallbacks.AFTER_SETTLE) {
            emit LogString("after settle");
            uint256 paid = abi.decode(lastReturnData, (uint256));
            _afterSettle(paid);
        } else if (cbType == ActionCallbacks.SHORTCUT_SETTLE) {
            emit LogString("shortcut settle");
            _shortcutSettle(abi.decode(cbData, (address)));
        } else if (cbType == ActionCallbacks.BEFORE_SETTLE_NATIVE) {
            emit LogString("before settle native");
            _beforeSettleNative(cbData);
        } else if (cbType == ActionCallbacks.AFTER_SETTLE_NATIVE) {
            emit LogString("after settle native");
            uint256 paid = abi.decode(lastReturnData, (uint256));
            _afterSettleNative(paid);
        } else if (cbType == ActionCallbacks.BEFORE_MINT) {
            emit LogString("before mint");
            _beforeMint(cbData);
        } else if (cbType == ActionCallbacks.AFTER_MINT) {
            emit LogString("after mint");
            _afterMint();
        } else if (cbType == ActionCallbacks.BEFORE_BURN) {
            emit LogString("before burn");
            _beforeBurn(cbData);
        } else if (cbType == ActionCallbacks.AFTER_BURN) {
            emit LogString("after burn");
            _afterBurn();
        } else if (cbType == ActionCallbacks.BEFORE_SYNC) {
            emit LogString("before sync");
            _beforeSync(cbData);
        } else if (cbType == ActionCallbacks.AFTER_SYNC) {
            emit LogString("after sync");
            _afterSync();
        } else if (cbType == ActionCallbacks.BEFORE_CLEAR) {
            emit LogString("before clear");
            _beforeClear(cbData);
        } else if (cbType == ActionCallbacks.AFTER_CLEAR) {
            emit LogString("after clear");
            _afterClear();
        } /* Protocol fee collection properties are disabled due to the fixes from TOB-UNI4-3
        else if (cbType == ActionCallbacks.SET_NEW_PROTOCOL_FEE) {
            emit LogString("set new protocol fee");
            _setNewProtocolFee(cbData);
        } else if (cbType == ActionCallbacks.COLLECT_PROTOCOL_FEES) {
            emit LogString("collect protocol fees");
            _collectProtocolFees(cbData);
        }*/ else if (cbType == ActionCallbacks.AFTER_TRANSFER_FROM) {
            (Currency c, uint256 amount, address from, address to) = abi.decode(cbData, (Currency, uint256, address, address));
            emit LogString("after transfer from");
            _afterTransferFrom(c, amount, from, to);
        } else {
            assertWithMsg(false, "unknown callback action");
        }
    }


    function updatePoolDynamicLpFee(uint8 poolIdx, uint24 fee) public {
        PoolKey memory poolKey = _clampToValidPool(poolIdx);
        manager.updateDynamicLPFee(poolKey, fee);
        emit LogUint256("modified pool's dynamic fee to ", fee);
    }

    /* The following functions act as "shortcuts" and give the fuzzer a better chance of creating a valid runActions sequence. */

    /// @notice This function eases coverage generation by adding a new pool and initializing it
    function addInitializeAndAddLiquidity(uint8 currency1I, uint8 currency2I, int24 tickSpacing, uint160 startPrice, uint24 fee, int24 minTick, int24 maxTick, int128 liqDelta, uint256 salt) public {
        addInitialize(currency1I, currency2I, tickSpacing, startPrice, fee);
        uint poolIdx = DeployedPools.length-1;
        emit LogUint256("poolidx", poolIdx);
        addModifyPosition(uint8(poolIdx), minTick, maxTick, liqDelta, salt);
    }

    /// @notice Doing everything addInitializeAndAddLiquidity does & settle the deltas.
    function addInitializeAndAddLiquidityAndSettle(uint8 currency1I, uint8 currency2I, int24 tickSpacing, uint160 startPrice, uint24 fee, int24 minTick, int24 maxTick, int128 liqDelta, uint256 salt) public {
        addInitializeAndAddLiquidity(currency1I, currency2I, tickSpacing, startPrice, fee, minTick, maxTick, liqDelta, salt);
        runActionsWithShortcutSettle();
    }

    /// @notice Swap into and out of a pair, then settling the deltas.
    function addSwapInSwapOut(uint8 poolIdx, bool zeroForOne, int256 amount) public {
        if(amount < 0) {
            amount = amount * -1;
        }
        // exact amount out
        addSwap(poolIdx, -amount, zeroForOne);
        // exact amount in
        addSwap(poolIdx, amount, !zeroForOne);

        addShortcutSettle();
    }

    /// @notice Creates a pool of highly concentrated liquidity.
    function addTargetedPool(uint8 currency1I, uint8 currency2I, uint24 fee, int128 liqDelta) public {
        if (liqDelta < 0){
            liqDelta = -liqDelta;
        }
        // concentrate the liquidity on 0,1
        addInitializeAndAddLiquidityAndSettle(currency1I, currency2I, 1, 79228162514264337593543950336, fee, 0, 1, liqDelta, 0);
    }

    /// @notice Creates a pool of highly concentrated liquidity with feeGrowthGlobal values that are close to overflowing
    function addTargetedPoolReadyToOverflow(uint8 currency1I, uint8 currency2I, uint24 fee) public {
        addTargetedPool(currency1I, currency2I, fee, 1);
        runActionsWithShortcutSettle();
        uint8 poolIdx = uint8(DeployedPools.length-1);

        addDonate(poolIdx, uint128(type(int128).max), uint128(type(int128).max));
        runActionsWithShortcutSettle();

        addDonate(poolIdx, uint128(type(int128).max), uint128(type(int128).max));
        runActionsWithShortcutSettle();
    }

    /// @notice Performs a donation, then settles and runs the action sequence.
    function addDonateAndSettle(uint256 amount0, uint256 amount1) public {
        uint8 poolIdx = uint8(DeployedPools.length-1);
        addDonate(poolIdx, amount0, amount1);
        runActionsWithShortcutSettle();
    }

    /// @notice This custom action is used to automatically settle all of the actor's outstanding deltas.
    function addShortcutSettle() public {
        address actor = address(actionsRouter);

        bytes memory shortcutSettleCBParam = abi.encode(address(this), abi.encode(ActionCallbacks.SHORTCUT_SETTLE, abi.encode(actor)));
        actions.push(Actions.HARNESS_CALLBACK);
        params.push(shortcutSettleCBParam);

    }

    /// @notice Settles the actor's outstanding deltas and runs the actions sequence.
    function runActionsWithShortcutSettle() public {
        addShortcutSettle();
        runActions();
    }

    /// @notice Performs a swap, settles the actor's balances, and runs the actions.
    function addSwapAndRunActions(uint8 poolIdx, int256 amountSpecified, bool zeroForOne) public {
        addSwap(poolIdx, amountSpecified, zeroForOne);
	    addShortcutSettle();
        runActions();
    }

    /// @notice Performs a burn, settles the actor's balances, and runs the actions.
    function addBurnAndRunActions(address from, uint8 curIdx, uint256 amount) public {
        addBurn(from, curIdx, amount);
 	    addShortcutSettle();
        runActions();
    } 

    /// @notice Performs a liquidity modification, settles the actor's balances, and runs the actions.
    function addModifyPositionAndRunActions(uint8 poolIdx, int24 lowTick, int24 highTick, int128 liqDelta, uint256 salt) public {
        addModifyPosition(poolIdx, lowTick, highTick, liqDelta, salt);
  	    addShortcutSettle();
        runActions();
    } 

    
    function _shortcutSettle(address actor) internal {
        for( uint i=0; i<Currencies.length; i++) {
            Currency c = Currencies[i];
            int256 delta = manager.currencyDelta(actor, c);

            if(delta < 0) {
                manager.sync(c);
                
                // manually reset remittances
                if(!(c == CurrencyLibrary.ADDRESS_ZERO)){
                    RemittanceCurrency = c;
                    RemittanceAmount = 0;
                }

                uint256 amountOwed = uint256(-delta);
                if( c == CurrencyLibrary.ADDRESS_ZERO) {
                    emit LogUint256("sending native tokens to manager:", amountOwed);
                    manager.settleFor{value: amountOwed}(actor);
                } else {
                    emit LogUint256("sending tokens to manager:", amountOwed);
                    c.transfer( address(manager), amountOwed);
                    manager.settleFor(actor);
                }
                emit LogString("resetting remittance settleForshortcut");
                RemittanceCurrency = CurrencyLibrary.ADDRESS_ZERO;
                RemittanceAmount = 0;
                

                _addToActorsCredits(actor, c, amountOwed);
            } else if (delta > 0) {
                emit LogUint256("take tokens:", uint256(delta));
                vm.prank(actor);
                manager.take(c, address(actor), uint256(delta));
                _addToActorsDebts(actor, c, uint256(delta));
            }
        }
    }
}