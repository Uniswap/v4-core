// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Hooks} from "../../contracts/libraries/Hooks.sol";
import {MockHooks} from "../../contracts/test/MockHooks.sol";
import {IPoolManager} from "../../contracts/interfaces/IPoolManager.sol";
import {TestERC20} from "../../contracts/test/TestERC20.sol";
import {IHooks} from "../../contracts/interfaces/IHooks.sol";
import {Currency} from "../../contracts/libraries/CurrencyLibrary.sol";
import {IERC20Minimal} from "../../contracts/interfaces/external/IERC20Minimal.sol";
import {PoolManager} from "../../contracts/PoolManager.sol";
import {SqrtPriceMath} from "../../contracts/libraries/SqrtPriceMath.sol";
import {PoolModifyPositionTest} from "../../contracts/test/PoolModifyPositionTest.sol";
import {PoolSwapTest} from "../../contracts/test/PoolSwapTest.sol";
import {PoolDonateTest} from "../../contracts/test/PoolDonateTest.sol";
import {Deployers} from "./utils/Deployers.sol";

contract HooksTest is Test, Deployers {
    address payable ALL_HOOKS_ADDRESS = payable(0xfF00000000000000000000000000000000000000);
    uint160 constant SQRT_RATIO_1_1 = 79228162514264337593543950336;
    MockHooks mockHooks;
    PoolManager manager;
    IPoolManager.PoolKey key;
    PoolModifyPositionTest modifyPositionRouter;
    PoolSwapTest swapRouter;
    PoolDonateTest donateRouter;

    function setUp() public {
        MockHooks impl = new MockHooks();
        vm.etch(ALL_HOOKS_ADDRESS, address(impl).code);
        mockHooks = MockHooks(ALL_HOOKS_ADDRESS);
        (manager, key,) = Deployers.createFreshPool(mockHooks, 3000, SQRT_RATIO_1_1);
        modifyPositionRouter = new PoolModifyPositionTest(IPoolManager(address(manager)));
        swapRouter = new PoolSwapTest(IPoolManager(address(manager)));
        donateRouter = new PoolDonateTest(IPoolManager(address(manager)));
    }

    function testInitializeSucceedsWithHook() public {
        (PoolManager _manager,, bytes32 id) = Deployers.createFreshPool(mockHooks, 3000, SQRT_RATIO_1_1);
        (uint160 sqrtPriceX96,,) = _manager.getSlot0(id);
        assertEq(sqrtPriceX96, SQRT_RATIO_1_1);
    }

    function testFailBeforeInitializeInvalidReturn() public {
        mockHooks.setReturnValue(mockHooks.beforeInitialize.selector, bytes4(0xdeadbeef));
        Deployers.createFreshPool(mockHooks, 3000, SQRT_RATIO_1_1);
    }

    function testFailAfterInitializeInvalidReturn() public {
        mockHooks.setReturnValue(mockHooks.afterInitialize.selector, bytes4(0xdeadbeef));
        Deployers.createFreshPool(mockHooks, 3000, SQRT_RATIO_1_1);
    }

    function testModifyPositionSucceedsWithHook() public {
        TestERC20(Currency.unwrap(key.currency0)).mint(address(this), 10 ** 18);
        IERC20Minimal(Currency.unwrap(key.currency0)).approve(address(modifyPositionRouter), 10 ** 18);
        modifyPositionRouter.modifyPosition(key, IPoolManager.ModifyPositionParams(0, 60, 100));
    }

    function testFailBeforeModifyPositionInvalidReturn() public {
        mockHooks.setReturnValue(mockHooks.beforeModifyPosition.selector, bytes4(0xdeadbeef));
        TestERC20(Currency.unwrap(key.currency0)).mint(address(this), 10 ** 18);
        IERC20Minimal(Currency.unwrap(key.currency0)).approve(address(modifyPositionRouter), 10 ** 18);
        modifyPositionRouter.modifyPosition(key, IPoolManager.ModifyPositionParams(0, 60, 100));
    }

    function testFailAfterModifyPositionInvalidReturn() public {
        mockHooks.setReturnValue(mockHooks.afterModifyPosition.selector, bytes4(0xdeadbeef));
        TestERC20(Currency.unwrap(key.currency0)).mint(address(this), 10 ** 18);
        IERC20Minimal(Currency.unwrap(key.currency0)).approve(address(modifyPositionRouter), 10 ** 18);
        modifyPositionRouter.modifyPosition(key, IPoolManager.ModifyPositionParams(0, 60, 100));
    }

    function testSwapSucceedsWithHook() public {
        TestERC20(Currency.unwrap(key.currency0)).mint(address(this), 10 ** 18);
        IERC20Minimal(Currency.unwrap(key.currency0)).approve(address(swapRouter), 10 ** 18);
        swapRouter.swap(
            key, IPoolManager.SwapParams(false, 100, SQRT_RATIO_1_1 + 60), PoolSwapTest.TestSettings(false, false)
        );
    }

    function testFailBeforeSwapInvalidReturn() public {
        mockHooks.setReturnValue(mockHooks.beforeSwap.selector, bytes4(0xdeadbeef));
        TestERC20(Currency.unwrap(key.currency0)).mint(address(this), 10 ** 18);
        IERC20Minimal(Currency.unwrap(key.currency0)).approve(address(swapRouter), 10 ** 18);
        swapRouter.swap(
            key, IPoolManager.SwapParams(false, 100, SQRT_RATIO_1_1 + 60), PoolSwapTest.TestSettings(false, false)
        );
    }

    function testFailAfterSwapInvalidReturn() public {
        mockHooks.setReturnValue(mockHooks.afterSwap.selector, bytes4(0xdeadbeef));
        TestERC20(Currency.unwrap(key.currency0)).mint(address(this), 10 ** 18);
        IERC20Minimal(Currency.unwrap(key.currency0)).approve(address(swapRouter), 10 ** 18);
        swapRouter.swap(
            key, IPoolManager.SwapParams(false, 100, SQRT_RATIO_1_1 + 60), PoolSwapTest.TestSettings(false, false)
        );
    }

    function testDonateSucceedsWithHook() public {
        addLiquidity(0, 60, 100);

        IERC20Minimal(Currency.unwrap(key.currency0)).approve(address(donateRouter), 100);
        IERC20Minimal(Currency.unwrap(key.currency1)).approve(address(donateRouter), 200);
        donateRouter.donate(key, 100, 200);
    }

    function testFailBeforeDonateInvalidReturn() public {
        mockHooks.setReturnValue(mockHooks.beforeDonate.selector, bytes4(0xdeadbeef));
        addLiquidity(0, 60, 100);

        IERC20Minimal(Currency.unwrap(key.currency0)).approve(address(donateRouter), 100);
        IERC20Minimal(Currency.unwrap(key.currency1)).approve(address(donateRouter), 200);
        donateRouter.donate(key, 100, 200);
    }

    function testFailAfterDonateInvalidReturn() public {
        mockHooks.setReturnValue(mockHooks.beforeDonate.selector, bytes4(0xdeadbeef));
        addLiquidity(0, 60, 100);

        IERC20Minimal(Currency.unwrap(key.currency0)).approve(address(donateRouter), 100);
        IERC20Minimal(Currency.unwrap(key.currency1)).approve(address(donateRouter), 200);
        donateRouter.donate(key, 100, 200);
    }

    function addLiquidity(int24 tickLower, int24 tickUpper, int256 amount) internal {
        TestERC20(Currency.unwrap(key.currency0)).mint(address(this), 10 ** 18);
        TestERC20(Currency.unwrap(key.currency1)).mint(address(this), 10 ** 18);
        IERC20Minimal(Currency.unwrap(key.currency0)).approve(address(modifyPositionRouter), 10 ** 18);
        IERC20Minimal(Currency.unwrap(key.currency1)).approve(address(modifyPositionRouter), 10 ** 18);
        modifyPositionRouter.modifyPosition(key, IPoolManager.ModifyPositionParams(tickLower, tickUpper, amount));
    }
}
