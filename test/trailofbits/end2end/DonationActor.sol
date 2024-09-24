// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {IHooks} from "src/interfaces/IHooks.sol";
import {Hooks} from "src/libraries/Hooks.sol";
import {IPoolManager} from "src/interfaces/IPoolManager.sol";

import {CurrencyLibrary, Currency} from "src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "src/types/PoolId.sol";
import {PoolKey} from "src/types/PoolKey.sol";
import {BalanceDelta} from "src/types/BalanceDelta.sol";
import {StateLibrary} from "src/libraries/StateLibrary.sol";
import {LPFeeLibrary} from "src/libraries/LPFeeLibrary.sol";

import {PoolTestBase} from "src/test/PoolTestBase.sol";
import {PoolModifyLiquidityTest} from "src/test/PoolModifyLiquidityTest.sol";
import {Deployers} from "test/utils/Deployers.sol";
import {CurrencySettler} from "test/utils/CurrencySettler.sol";

import {IActor} from "./IActor.sol";
import {PropertiesAsserts} from "../PropertiesHelper.sol";
import {SwapInfo, SwapInfoLibrary} from "./Lib.sol";


contract DonationActor is PropertiesAsserts, PoolTestBase, IActor {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;
    using Hooks for IHooks;
    using LPFeeLibrary for uint24;

    address Harness;

    constructor(IPoolManager _manager) PoolTestBase(_manager) {
        Harness = msg.sender;
    }
    
    struct CallbackData {
        address sender;
        PoolKey key;
        uint256 amount0;
        uint256 amount1;
        bytes hookData;
    }

    function Donate(PoolKey memory key, uint256 amount0, uint256 amount1)
        external
        payable
        returns (BalanceDelta delta)
    {
        delta = abi.decode(
            manager.unlock(abi.encode(CallbackData(msg.sender, key, amount0, amount1, new bytes(0)))), (BalanceDelta)
        );

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.ADDRESS_ZERO.transfer(msg.sender, ethBalance);
        }
    }



    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        (,, int256 deltaBefore0) = _fetchBalances(data.key.currency0, data.sender, address(this));
        (,, int256 deltaBefore1) = _fetchBalances(data.key.currency1, data.sender, address(this));

        require(deltaBefore0 == 0, "deltaBefore0 is not 0");
        require(deltaBefore1 == 0, "deltaBefore1 is not 0");

        BalanceDelta delta = manager.donate(data.key, data.amount0, data.amount1, data.hookData);

        (,, int256 deltaAfter0) = _fetchBalances(data.key.currency0, data.sender, address(this));
        (,, int256 deltaAfter1) = _fetchBalances(data.key.currency1, data.sender, address(this));

        require(deltaAfter0 == -int256(data.amount0), "deltaAfter0 is not equal to -int256(data.amount0)");
        require(deltaAfter1 == -int256(data.amount1), "deltaAfter1 is not equal to -int256(data.amount1)");


        if (deltaAfter0 < 0) {
            // obtain tokens from harness
            MockERC20(Currency.unwrap(data.key.currency0)).transferFrom(Harness, address(this), uint256(-deltaAfter0));
            CurrencySettler.settle(data.key.currency0, manager, data.sender, uint256(-deltaAfter0), false);
        } 
        if (deltaAfter1 < 0){ 
            // obtain tokens from harness
            MockERC20(Currency.unwrap(data.key.currency1)).transferFrom(Harness, address(this), uint256(-deltaAfter1));
            CurrencySettler.settle(data.key.currency1, manager, data.sender, uint256(-deltaAfter1), false);
        }
        if (deltaAfter0 > 0) {
            // unhittable?
            assert(false);
            CurrencySettler.take(data.key.currency0, manager, data.sender, uint256(deltaAfter0), false);
            // send tokens back to harness
            data.key.currency0.transfer(Harness, uint256(deltaAfter0));
        }
        if (deltaAfter1 > 0){ 
            // unhittable?
            assert(false);
            CurrencySettler.take(data.key.currency1, manager, data.sender, uint256(deltaAfter1), false);
            // send tokens back to harness
            data.key.currency1.transfer( Harness, uint256(deltaAfter1));
        }

        return abi.encode(delta);
    }

    function proxyApprove(Currency token, address spender) public {
        MockERC20(Currency.unwrap(token)).approve(spender, type(uint256).max);
    }

}