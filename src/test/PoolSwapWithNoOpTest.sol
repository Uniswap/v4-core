// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {CurrencyLibrary, Currency} from "../types/Currency.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../types/BalanceDelta.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {Hooks} from "../libraries/Hooks.sol";
import {PoolTestBase} from "./PoolTestBase.sol";
import {Test} from "forge-std/Test.sol";
import {Hooks} from "../libraries/Hooks.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {SafeCast} from "../libraries/SafeCast.sol";

contract PoolSwapWithNoOpTest is Test, PoolTestBase {
    using CurrencyLibrary for Currency;
    using Hooks for IHooks;
    using SafeCast for uint256;
    using SafeCast for int256;

    constructor(IPoolManager _manager) PoolTestBase(_manager) {}

    uint256 public constant TOTAL_DEBT = uint256(0);

    error NoSwapOccurred();

    struct CallbackData {
        address sender;
        PoolKey key;
        IPoolManager.SwapParams params;
    }

    function swap(PoolKey memory key, IPoolManager.SwapParams memory params)
        external
        payable
        returns (BalanceDelta delta)
    {
        delta =
            abi.decode(manager.lock(address(this), abi.encode(CallbackData(msg.sender, key, params))), (BalanceDelta));

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
    }

    function lockAcquired(address sender, bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));
        sender = (sender == address(this)) ? data.sender : sender;

        BalanceDelta delta = manager.swap(data.key, data.params, "");
        // check the swap was no-oped
        require(delta == BalanceDeltaLibrary.MAXIMUM_DELTA);

        Currency currencyIn = data.params.zeroForOne ? data.key.currency0 : data.key.currency1;
        Currency currencyOut = data.params.zeroForOne ? data.key.currency1 : data.key.currency0;

        int256 inputDelta = manager.currencyDelta(address(data.key.hooks), currencyIn);
        int256 outputDelta = manager.currencyDelta(address(this), currencyOut);

        // check that the hook has an input token debt, and this address is owed output tokens
        require(inputDelta > 0 && outputDelta < 0);

        // move the hook's input debt to this address and then settle it
        manager.payOnBehalf(currencyIn, address(data.key.hooks), uint256(inputDelta));
        _settle(currencyIn, sender, inputDelta.toInt128(), true);

        // take the input tokens
        _take(currencyOut, sender, outputDelta.toInt128(), true);

        return abi.encode(delta);
    }
}
