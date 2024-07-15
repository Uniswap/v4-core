// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {Deployers} from "./utils/Deployers.sol";
import {Actions} from "../src/test/ActionsRouter.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import {Currency} from "../src/types/Currency.sol";

contract ClearTest is Test, Deployers {
    function setUp() public {
        initializeManagerRoutersAndPoolsWithLiq(IHooks(address(0)));
        seedMoreLiquidity(key, 10e18, 10e18);
    }

    function test_clear_reverts_negativeDelta() external {
        uint256 amount = 1e18;

        Actions[] memory actions = new Actions[](2);
        bytes[] memory params = new bytes[](2);

        // Apply a negative delta.
        actions[0] = Actions.TAKE;
        params[0] = abi.encode(currency0, address(this), amount);

        actions[1] = Actions.CLEAR;
        params[1] = abi.encode(currency0, amount, false, "");

        vm.expectRevert(IPoolManager.MustClearExactPositiveDelta.selector);
        actionsRouter.executeActions(actions, params);
    }

    function test_clear_reverts_positiveDelta_inputGreaterThanDelta() external {
        uint256 amount = 1e18;
        Actions[] memory actions = new Actions[](5);
        bytes[] memory params = new bytes[](5);

        // Apply a positive delta.
        actions[0] = Actions.SYNC;
        params[0] = abi.encode(currency0);

        actions[1] = Actions.TRANSFER_FROM;
        params[1] = abi.encode(currency0, address(this), address(manager), amount);

        actions[2] = Actions.SETTLE;
        params[2] = abi.encode(currency0);

        // Delta should be equal to the positive amount.
        actions[3] = Actions.ASSERT_DELTA_EQUALS;
        params[3] = abi.encode(currency0, address(actionsRouter), amount);

        // Clear for 1 greater than the delta.
        actions[4] = Actions.CLEAR;
        params[4] = abi.encode(currency0, amount + 1, false, "");

        vm.expectRevert(IPoolManager.MustClearExactPositiveDelta.selector);
        actionsRouter.executeActions(actions, params);
    }

    function test_clear_reverts_positiveDelta_inputLessThanDelta() external {
        uint256 amount = 1e18;
        Actions[] memory actions = new Actions[](5);
        bytes[] memory params = new bytes[](5);

        // Apply a positive delta.
        actions[0] = Actions.SYNC;
        params[0] = abi.encode(currency0);

        actions[1] = Actions.TRANSFER_FROM;
        params[1] = abi.encode(currency0, address(this), address(manager), amount);

        actions[2] = Actions.SETTLE;
        params[2] = abi.encode(currency0);

        actions[3] = Actions.ASSERT_DELTA_EQUALS;
        params[3] = abi.encode(currency0, address(actionsRouter), amount);

        // Clear for 1 less than the delta.
        actions[4] = Actions.CLEAR;
        params[4] = abi.encode(currency0, amount - 1, false, "");

        vm.expectRevert(IPoolManager.MustClearExactPositiveDelta.selector);
        actionsRouter.executeActions(actions, params);
    }

    function test_clear_reverts_positiveDelta_inputZero() external {
        uint256 amount = 1e18;
        Actions[] memory actions = new Actions[](5);
        bytes[] memory params = new bytes[](5);

        // Apply a positive delta.
        actions[0] = Actions.SYNC;
        params[0] = abi.encode(currency0);

        actions[1] = Actions.TRANSFER_FROM;
        params[1] = abi.encode(currency0, address(this), address(manager), amount);

        actions[2] = Actions.SETTLE;
        params[2] = abi.encode(currency0);

        actions[3] = Actions.ASSERT_DELTA_EQUALS;
        params[3] = abi.encode(currency0, address(actionsRouter), amount);

        // Clear with 0.
        actions[4] = Actions.CLEAR;
        params[4] = abi.encode(currency0, 0, false, "");

        vm.expectRevert(IPoolManager.MustClearExactPositiveDelta.selector);
        actionsRouter.executeActions(actions, params);
    }

    function test_clear_zeroDelta_inputZero_isUnchanged() external {
        Actions[] memory actions = new Actions[](5);
        bytes[] memory params = new bytes[](5);

        actions[0] = Actions.ASSERT_NONZERO_DELTA_COUNT_EQUALS;
        params[0] = abi.encode(0);

        actions[1] = Actions.ASSERT_DELTA_EQUALS;
        params[1] = abi.encode(currency0, address(actionsRouter), 0);

        // Clear with 0.
        actions[2] = Actions.CLEAR;
        params[2] = abi.encode(currency0, 0, false, "");

        actions[3] = Actions.ASSERT_DELTA_EQUALS;
        params[3] = abi.encode(currency0, address(actionsRouter), 0);

        actions[4] = Actions.ASSERT_NONZERO_DELTA_COUNT_EQUALS;
        params[4] = abi.encode(0);

        actionsRouter.executeActions(actions, params);
    }

    function test_clear_reverts_zeroDelta_inputNonZero() external {
        uint256 amount = 1e18;
        Actions[] memory actions = new Actions[](3);
        bytes[] memory params = new bytes[](3);

        actions[0] = Actions.ASSERT_NONZERO_DELTA_COUNT_EQUALS;
        params[0] = abi.encode(0);

        actions[1] = Actions.ASSERT_DELTA_EQUALS;
        params[1] = abi.encode(currency0, address(actionsRouter), 0);

        // Clear with nonZero.
        actions[2] = Actions.CLEAR;
        params[2] = abi.encode(currency0, amount, false, "");

        vm.expectRevert(IPoolManager.MustClearExactPositiveDelta.selector);
        actionsRouter.executeActions(actions, params);
    }

    function test_clear_positiveDelta_inputExact_succeeds() external {
        uint256 amount = 1e18;
        Actions[] memory actions = new Actions[](8);
        bytes[] memory params = new bytes[](8);

        // Apply a positive delta.
        actions[0] = Actions.SYNC;
        params[0] = abi.encode(currency0);

        actions[1] = Actions.TRANSFER_FROM;
        params[1] = abi.encode(currency0, address(this), address(manager), amount);

        actions[2] = Actions.SETTLE;
        params[2] = abi.encode(currency0);

        // Delta should be equal to the positive amount.
        actions[3] = Actions.ASSERT_DELTA_EQUALS;
        params[3] = abi.encode(currency0, address(actionsRouter), amount);

        // Assert nonzero delta count is 1.
        actions[4] = Actions.ASSERT_NONZERO_DELTA_COUNT_EQUALS;
        params[4] = abi.encode(1);

        // Clear the exact delta amount.
        actions[5] = Actions.CLEAR;
        params[5] = abi.encode(currency0, amount, false, "");

        actions[6] = Actions.ASSERT_DELTA_EQUALS;
        params[6] = abi.encode(currency0, address(actionsRouter), 0);

        actions[7] = Actions.ASSERT_NONZERO_DELTA_COUNT_EQUALS;
        params[7] = abi.encode(0);

        actionsRouter.executeActions(actions, params);
    }

    function test_clear_gas() external {
        uint256 amount = 1e18;
        Actions[] memory actions = new Actions[](8);
        bytes[] memory params = new bytes[](8);

        // Apply a positive delta.
        actions[0] = Actions.SYNC;
        params[0] = abi.encode(currency0);

        actions[1] = Actions.TRANSFER_FROM;
        params[1] = abi.encode(currency0, address(this), address(manager), amount);

        actions[2] = Actions.SETTLE;
        params[2] = abi.encode(currency0);

        // Delta should be equal to the positive amount.
        actions[3] = Actions.ASSERT_DELTA_EQUALS;
        params[3] = abi.encode(currency0, address(actionsRouter), amount);

        // Assert nonzero delta count is 1.
        actions[4] = Actions.ASSERT_NONZERO_DELTA_COUNT_EQUALS;
        params[4] = abi.encode(1);

        // Clear the exact delta amount.
        actions[5] = Actions.CLEAR;
        params[5] = abi.encode(currency0, amount, true, "clear");

        actions[6] = Actions.ASSERT_DELTA_EQUALS;
        params[6] = abi.encode(currency0, address(actionsRouter), 0);

        actions[7] = Actions.ASSERT_NONZERO_DELTA_COUNT_EQUALS;
        params[7] = abi.encode(0);

        actionsRouter.executeActions(actions, params);
    }
}
