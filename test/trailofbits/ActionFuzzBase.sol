// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Base.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {IPoolManager} from "src/interfaces/IPoolManager.sol";

import {CurrencyLibrary, Currency} from "src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "src/types/PoolId.sol";
import {PoolKey} from "src/types/PoolKey.sol";

import {Pool} from "src/libraries/Pool.sol";
import {StateLibrary} from "src/libraries/StateLibrary.sol";
import {TickMath} from "src/libraries/TickMath.sol";
import {TransientStateLibrary} from "src/libraries/TransientStateLibrary.sol";

import {Actions, ActionsRouter, ActionsRouterNoGasMeasurement} from "src/test/ActionsRouter.sol";
import {Deployers} from "test/utils/Deployers.sol";
import {ProtocolFeeControllerTest} from "src/test/ProtocolFeeControllerTest.sol";
import {PropertiesAsserts} from "test/trailofbits/PropertiesHelper.sol";
import {V4StateMachine} from "test/trailofbits/V4StateMachine.sol";
import {ShadowAccounting} from "test/trailofbits/ShadowAccounting.sol";


enum ActionCallbacks {
    BEFORE_DONATE,
    AFTER_DONATE,
    BEFORE_INITIALIZE,
    AFTER_INITIALIZE,
    BEFORE_SWAP,
    AFTER_SWAP,
    BEFORE_MODIFY_POSITION,
    AFTER_MODIFY_POSITION,
    BEFORE_TAKE,
    AFTER_TAKE,
    BEFORE_SETTLE,
    AFTER_SETTLE,
    BEFORE_SETTLE_NATIVE,
    AFTER_SETTLE_NATIVE,
    BEFORE_MINT,
    AFTER_MINT,
    BEFORE_BURN,
    AFTER_BURN,
    BEFORE_CLEAR,
    AFTER_CLEAR,
    BEFORE_SYNC,
    AFTER_SYNC,
    SHORTCUT_SETTLE,
    SET_NEW_PROTOCOL_FEE,
    COLLECT_PROTOCOL_FEES,
    AFTER_TRANSFER_FROM
}


contract ActionFuzzBase is V4StateMachine, ShadowAccounting, ScriptBase {
    using TransientStateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    PoolKey[] public DeployedPools;
    mapping(PoolId => bool) PoolInitialized;
    Currency[] public Currencies;


    // The fuzzer calls add<X> functions to add actions to the sequence with their corresponding parameters.
    Actions[] actions;
    bytes[] params;

    // We'll use these to "cache" sequences so we can run through multiple unlock/lock contexts in a single tx.
    // This might help sus out issues related to clearing transient storage.
    Actions[][] actionSequences;
    bytes[][] paramSequences;

    uint public NUMBER_CURRENCIES = 6;

    constructor() payable {
        deployFreshManager();
        // manually instantiate actionsRouter with the one that doesn't measure gas.
        actionsRouter = ActionsRouter(payable(address(new ActionsRouterNoGasMeasurement(manager))));
        feeController = new ProtocolFeeControllerTest();
        manager.setProtocolFeeController(feeController);

        // Initialize currencies
        for (uint i = 0; i < NUMBER_CURRENCIES; i++) {
            // we place the native currency at the end of our currencies array to protect the existing corpus.
            if (i == NUMBER_CURRENCIES-1) {
                Currencies.push(CurrencyLibrary.ADDRESS_ZERO);
            } else {
                MockERC20 token = deployTokens(1, 2 ** 255)[0];
                token.approve(address(actionsRouter), type(uint256).max);

                Currency c = Currency.wrap(address(token));
                Currencies.push(c);
            }
        }
    }

    function getActionRouter() public view returns (address) {
        return address(actionsRouter);
    }

    function getManager() public view returns (address) {
        return address(manager);
    }


    function runActions() public {
        // start running actions from our stored sequences
        for(uint i=0; i<actionSequences.length; i++) {
            Actions[] memory a = actionSequences[i];
            bytes[] memory p = paramSequences[i];
            actionsRouter.executeActions(a, p);
   
            // UNI-E2E-1    
            assertEq(OutstandingDeltas, 0, "Outstanding deltas must be zero after the singleton is re-locked.");
        }

        // run whatever's in the current sequence
        actionsRouter.executeActions(actions, params);

        // UNI-E2E-1      
        assertEq(OutstandingDeltas, 0, "Outstanding deltas must be zero after the singleton is re-locked.");
        _coverageNudge();
        delete actions;
        delete params;
        delete actionSequences;
        delete paramSequences;
        _clearTransientRemittances();
        emit LogString("pool key");
        if(DeployedPools.length > 0) {
            emit LogBytes(abi.encode(DeployedPools[0].toId()));
        }
    }

    function prepareNewLock() public {
        // store the current sequence
        actionSequences.push(actions);
        paramSequences.push(params);
        delete actions;
        delete params;
    }


    function _coverageNudge() internal {
        for(uint i=0; i<actions.length; i++){
            if(actions[i] == Actions.SETTLE){
                emit LogString("We did a SETTLE and it worked!");
            } else if (actions[i] == Actions.SETTLE_NATIVE){
                emit LogString("We did a SETTLE_NATIVE and it worked!");    
            } else if (actions[i] == Actions.SETTLE_FOR){
                emit LogString("We did a SETTLE_FOR and it worked!");    
            } else if (actions[i] == Actions.TAKE){
                emit LogString("We did a TAKE and it worked!");    
            } else if (actions[i] == Actions.SYNC){
                emit LogString("We did a SYNC and it worked!");    
            } else if (actions[i] == Actions.MINT){
                emit LogString("We did a MINT and it worked!");    
            } else if (actions[i] == Actions.BURN){
                emit LogString("We did a BURN and it worked!");    
            } else if (actions[i] == Actions.CLEAR){
                emit LogString("We did a CLEAR and it worked!");    
            } else if (actions[i] == Actions.TRANSFER_FROM){
                emit LogString("We did a TRANSFER_FROM and it worked!");    
            } else if (actions[i] == Actions.INITIALIZE){
                emit LogString("We did a INITIALIZE and it worked!");    
            } else if (actions[i] == Actions.DONATE){
                emit LogString("We did a DONATE and it worked!");    
            } else if (actions[i] == Actions.MODIFY_POSITION){
                emit LogString("We did a MODIFY_POSITION and it worked!");    
            } else if (actions[i] == Actions.SWAP){
                emit LogString("We did a SWAP and it worked!");    
            } else if (actions[i] == Actions.HARNESS_CALLBACK){
                emit LogString("We did a HARNESS_CALLBACK and it worked!");    
            }
        }
    }

    function _encodeHarnessCallback(ActionCallbacks cbType, bytes memory cbParams) internal view returns (bytes memory) {
        bytes memory harnessCbParamEncoded = abi.encode(
            cbType,
            cbParams
        );
        
        return abi.encode(
            address(this),
            harnessCbParamEncoded
        );
    }

    /// @notice While this function calls it a "clamp", we're technically using modulo so our input space is evenly distributed.
    function _clampToUsableTicks(int24 minTick, int24 maxTick, PoolKey memory poolKey) internal returns (int24, int24) {
        int24 minUsableTick = TickMath.minUsableTick(poolKey.tickSpacing);
        int24 maxUsableTick = TickMath.maxUsableTick(poolKey.tickSpacing);

        emit LogInt256("minUsableTick", minUsableTick);
        emit LogInt256("maxUsableTick", maxUsableTick);

        minTick = int24(clampBetween(minTick, minUsableTick, maxUsableTick));
        maxTick = int24(clampBetween(maxTick, minUsableTick, maxUsableTick));

        if (maxTick < minTick) {
            int24 tmp = minTick;
            minTick = maxTick;
            maxTick = tmp;
        }

        emit LogInt256("minTick", minTick);
        emit LogInt256("maxTick", maxTick);
        return (minTick, maxTick);
    }

    /// @notice While this function calls it a "clamp", we're technically using modulo so our input space is evenly distributed.
    function _clampToValidCurrencies(uint8 currency1I, uint8 currency2I) internal returns (Currency, Currency) {
        uint c1 = clampBetween(currency1I, 0, NUMBER_CURRENCIES-1);
        uint c2 = clampBetween(currency2I, 0, NUMBER_CURRENCIES-1);
        require(c1 != c2);

        Currency cur1 = Currencies[c1];
        Currency cur2 = Currencies[c2];
        if (cur1 >= cur2) {
            emit LogAddress("address 1", address(Currency.unwrap(cur2)));
            emit LogAddress("address 2", address(Currency.unwrap(cur1)));
            return (cur2, cur1);
        } else {
            emit LogAddress("address 1", address(Currency.unwrap(cur1)));
            emit LogAddress("address 2", address(Currency.unwrap(cur2)));
            return (cur1, cur2);
        }
    }

    /// @notice While this function calls it a "clamp", we're technically using modulo so our input space is evenly distributed.
    function _clampToValidPool(uint poolIndex) internal returns ( PoolKey memory) {
        poolIndex = clampBetween(poolIndex, 0, DeployedPools.length-1);
        emit LogUint256("Pool index", poolIndex);
        return DeployedPools[poolIndex];
    }


    /* Functions we want as an entrypoint for fuzzing, but do not verify properties for. */
    function addTransferFrom(uint8 currency1I, uint256 amount, address from, address to) public {
        Currency c1 = Currencies[clampBetween(currency1I, 0, NUMBER_CURRENCIES-1)];
        bytes memory param = abi.encode(c1, from, to, amount);
        actions.push(Actions.TRANSFER_FROM);
        params.push(param);

        bytes memory cbParams = abi.encode(c1, amount, from, to);
        actions.push(Actions.HARNESS_CALLBACK);
        params.push(_encodeHarnessCallback(ActionCallbacks.AFTER_TRANSFER_FROM, cbParams));
    }

    function _afterTransferFrom(Currency c, uint256 amount, address, address to) internal {
        if(c == RemittanceCurrency && to == address(manager)) {
            RemittanceAmount += int256(amount);
        }
    }

    /// @notice This function is used to verify various properties that should hold at all times while the singleton is unlocked.
    /// When fuzzing a new action, only call _verifyGlobalProperties after doing accounting for our copy of currency deltas,
    /// liquidity, etc.
    /// It may make more sense for this to live in ShadowAccounting.
    function _verifyGlobalProperties(address, Currency currency) internal {
        // the only actor in the system we owe money to right now is address(actionsRouter).
        // if this changes, we need to sum all currency deltas of all actors, not just actionsRouter

        int256 delta = manager.currencyDelta(address(actionsRouter), currency);
        uint256 singletonBalance = currency.balanceOf(address(manager));
        emit LogUint256("Global: singleton balance", singletonBalance);

        uint256 singletonBalanceInclDelta;
        if(delta > 0) {
            singletonBalanceInclDelta = singletonBalance - uint256(delta);
        } else {
            singletonBalanceInclDelta = singletonBalance + uint256(-delta);
        }
        emit LogUint256("Global: singleton balance incl delta", singletonBalanceInclDelta);
        emit LogUint256("Global: singleton liquidity", SingletonLiquidity[currency]);
        emit LogUint256("Global: singleton lp fees (in fee growth)", SingletonLPFees[currency]);
        emit LogInt256("Global: currencyDelta for actor", delta);

        assertGte(singletonBalanceInclDelta, SingletonLiquidity[currency], "Bug in harness? Probably turn this into a property.");
        
        if (delta >= 0) {
            // UNI-ACTION-1 (weak, no protocol fees)
            assertGte(singletonBalance - SingletonLiquidity[currency], uint256(delta), "The amount owed to an actor must always be less than or equal the balance of the singleton.");
        }     
        uint256 singletonBalanceAfterRelocking = _deltaAdd(singletonBalance, -delta);

        // This amount represents the amount of currency that would be remaining in the singleton if every LPer withdrew their liquidity and fees.
        uint256 balanceAvailableForProtocolFees = singletonBalanceAfterRelocking - SingletonLiquidity[currency] - SingletonLPFees[currency];
        uint256 protocolFees = manager.protocolFeesAccrued(currency);
        
        // UNI-ACTION-3 
        assertLte(protocolFees, balanceAvailableForProtocolFees, "The amount of protocol fees owed may not exceed the singleton's balance (less its deployed liquidity) while the currency has a positive or zero delta.");

        if (delta >= 0) {
            uint256 balanceAvailableForCreditors = singletonBalance - protocolFees - SingletonLiquidity[currency]- SingletonLPFees[currency];
            // UNI-ACTION-2 
            assertLte(delta, int256(balanceAvailableForCreditors), "The amount owed to an actor must always be less than or equal the balance of the singleton, less protocol fees and LP fees.");
        }
    }

    function _deltaAdd(uint256 a, int256 delta) internal returns (uint256 sum)  {
        unchecked {
            if(delta >= 0){
                sum = a + uint256(delta);
                assertGte(sum, a, "Sum overflow. This may be a bug in the harness, or an issue in v4.");
            } else {
                sum = a - uint256(-delta);
                assertLt(sum, a, "Sum underflow. This may be a bug in the harness, or an issue in v4.");
            }
        }
    }

    fallback() external payable {}
}