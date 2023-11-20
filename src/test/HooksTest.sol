// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Hooks} from "../libraries/Hooks.sol";
import {IHooks} from "../interfaces/IHooks.sol";

contract HooksTest {
    using Hooks for IHooks;

    function validateHookAddress(address hookAddress, Hooks.Calls calldata params) external pure {
        IHooks(hookAddress).validateHookAddress(params);
    }

    function isValidHookAddress(address hookAddress, uint24 fee) external pure returns (bool) {
        return IHooks(hookAddress).isValidHookAddress(fee);
    }

    function shouldCallBeforeInitialize(address hookAddress) external pure returns (bool) {
        return IHooks(hookAddress).shouldCallBeforeInitialize();
    }

    function shouldCallAfterInitialize(address hookAddress) external pure returns (bool) {
        return IHooks(hookAddress).shouldCallAfterInitialize();
    }

    function shouldCallBeforeSwap(address hookAddress) external pure returns (bool) {
        return IHooks(hookAddress).shouldCallBeforeSwap();
    }

    function shouldCallAfterSwap(address hookAddress) external pure returns (bool) {
        return IHooks(hookAddress).shouldCallAfterSwap();
    }

    function shouldCallBeforeMint(address hookAddress) external pure returns (bool) {
        return IHooks(hookAddress).shouldCallBeforeMint();
    }

    function shouldCallAfterMint(address hookAddress) external pure returns (bool) {
        return IHooks(hookAddress).shouldCallAfterMint();
    }

    function shouldCallBeforeBurn(address hookAddress) external pure returns (bool) {
        return IHooks(hookAddress).shouldCallBeforeBurn();
    }

    function shouldCallAfterBurn(address hookAddress) external pure returns (bool) {
        return IHooks(hookAddress).shouldCallAfterBurn();
    }

    function shouldCallBeforeDonate(address hookAddress) external pure returns (bool) {
        return IHooks(hookAddress).shouldCallBeforeDonate();
    }

    function shouldCallAfterDonate(address hookAddress) external pure returns (bool) {
        return IHooks(hookAddress).shouldCallAfterDonate();
    }

    function getGasCostOfShouldCall(address hookAddress) external view returns (uint256) {
        uint256 gasBefore = gasleft();
        IHooks(hookAddress).shouldCallBeforeSwap();
        return gasBefore - gasleft();
    }

    function getGasCostOfValidateHookAddress(address hookAddress, Hooks.Calls calldata params)
        external
        view
        returns (uint256)
    {
        uint256 gasBefore = gasleft();
        IHooks(hookAddress).validateHookAddress(params);
        return gasBefore - gasleft();
    }
}
