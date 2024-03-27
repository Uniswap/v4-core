// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "test/utils/Deployers.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Action} from "src/test/PoolNestedActionsTest.sol";
import {IHooks} from "src/interfaces/IHooks.sol";

contract NestedActions is Test, Deployers, GasSnapshot {
    Action[] actions;

    function setUp() public {
        initializeManagerRoutersAndPoolsWithLiq(IHooks(address(0)));
    }

    // Asserts and expected outcomes are tested inside the nestedActionRouter

    function test_nestedSwap() public {
        actions = [Action.SWAP_AND_SETTLE];
        nestedActionRouter.unlock(abi.encode(actions));
    }

    function test_nestedAddLiquidity() public {
        actions = [Action.ADD_LIQUIDITY_AND_SETTLE];
        nestedActionRouter.unlock(abi.encode(actions));
    }

    function test_nestedRemoveLiquidity() public {
        actions = [Action.ADD_LIQUIDITY_AND_SETTLE, Action.REMOVE_LIQUIDITY_AND_SETTLE];
        nestedActionRouter.unlock(abi.encode(actions));
    }

    function test_nestedDonate() public {
        actions = [Action.DONATE_AND_SETTLE];
        nestedActionRouter.unlock(abi.encode(actions));
    }

    function test_nestedInitialize() public {
        actions = [Action.INITIALIZE];
        nestedActionRouter.unlock(abi.encode(actions));
    }
}
