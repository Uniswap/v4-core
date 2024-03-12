// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Hooks} from "../libraries/Hooks.sol";
import {BaseTestHooks} from "./BaseTestHooks.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "../types/PoolId.sol";
import {FeeLibrary} from "../../src/libraries/FeeLibrary.sol";
import {IERC20Minimal} from "../interfaces/external/IERC20Minimal.sol";
import {CurrencyLibrary, Currency} from "../types/Currency.sol";
import {PoolTestBase} from "./PoolTestBase.sol";
import {Test} from "forge-std/Test.sol";

contract SkipCallsTestHook is BaseTestHooks, Test {
    using PoolIdLibrary for PoolKey;
    using Hooks for IHooks;
    using FeeLibrary for uint24;

    uint256 public counter;
    IPoolManager manager;
    uint24 internal fee;

    function setManager(IPoolManager _manager) external {
        manager = _manager;
    }

    function setFee(uint24 _fee) external {
        fee = _fee;
    }

    function getFee(address, PoolKey calldata) public view returns (uint24) {
        return fee;
    }

    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata hookData)
        external
        override
        returns (bytes4)
    {
        counter++;
        callSwap(key, params, hookData);
        return IHooks.beforeSwap.selector;
    }

    function callSwap(PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata hookData) public {
        IPoolManager(msg.sender).swap(key, params, hookData);
        address payer = abi.decode(hookData, (address));
        int256 delta0 = IPoolManager(msg.sender).currencyDelta(address(this), key.currency0);
        assertEq(delta0, params.amountSpecified);
        int256 delta1 = IPoolManager(msg.sender).currencyDelta(address(this), key.currency1);
        assert(delta1 < 0);
        IERC20Minimal(Currency.unwrap(key.currency0)).transferFrom(payer, msg.sender, uint256(delta0));
        manager.settle(key.currency0);
        manager.take(key.currency1, payer, uint256(-delta1));
    }
}
