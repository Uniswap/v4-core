// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Hooks} from "src/libraries/Hooks.sol";
import {LPFeeLibrary} from "src/libraries/LPFeeLibrary.sol";
import {MockHooks} from "src/test/MockHooks.sol";
import {IPoolManager} from "src/interfaces/IPoolManager.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {IHooks} from "src/interfaces/IHooks.sol";
import {Currency} from "src/types/Currency.sol";
import {PoolManager} from "src/PoolManager.sol";
import {PoolSwapTest} from "src/test/PoolSwapTest.sol";
import {PoolDonateTest} from "src/test/PoolDonateTest.sol";
import {Deployers} from "test/utils/Deployers.sol";
import {ProtocolFees} from "src/ProtocolFees.sol";
import {PoolId, PoolIdLibrary} from "src/types/PoolId.sol";
import {PoolKey} from "src/types/PoolKey.sol";
import {IERC20Minimal} from "src/interfaces/external/IERC20Minimal.sol";
import {BalanceDelta} from "src/types/BalanceDelta.sol";
import {StateLibrary} from "src/libraries/StateLibrary.sol";

contract HooksIntegrationTest is Test, Deployers, GasSnapshot {
    using PoolIdLibrary for PoolKey;
    using Hooks for IHooks;
    using StateLibrary for IPoolManager;

    /// 1111 1111 1111 1100
    address payable private ALL_HOOKS_ADDRESS = payable(0xFffC000000000000000000000000000000000000);
    MockHooks private mockHooks;

    function setUp() external {
        MockHooks impl = new MockHooks();
        vm.etch(ALL_HOOKS_ADDRESS, address(impl).code);
        mockHooks = MockHooks(ALL_HOOKS_ADDRESS);

        initializeManagerRoutersAndPoolsWithLiq(mockHooks);
    }

    function test_initialize_succeedsWithHook() external {
        manager.initialize(uninitializedKey, SQRT_PRICE_1_1, new bytes(123));

        (uint160 sqrtPriceX96,,,) = manager.getSlot0(uninitializedKey.toId());
        assertEq(sqrtPriceX96, SQRT_PRICE_1_1);
        assertEq(mockHooks.beforeInitializeData(), new bytes(123));
        assertEq(mockHooks.afterInitializeData(), new bytes(123));
    }

    function test_beforeInitialize_invalidReturn() external {
        mockHooks.setReturnValue(mockHooks.beforeInitialize.selector, bytes4(0xdeadbeef));
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        manager.initialize(uninitializedKey, SQRT_PRICE_1_1, ZERO_BYTES);
    }

    function test_afterInitialize_invalidReturn() external {
        mockHooks.setReturnValue(mockHooks.afterInitialize.selector, bytes4(0xdeadbeef));
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        manager.initialize(uninitializedKey, SQRT_PRICE_1_1, ZERO_BYTES);
    }

    function test_beforeAfterAddLiquidity_beforeAfterRemoveLiquidity_succeedsWithHook() external {
        MockERC20(Currency.unwrap(key.currency0)).mint(address(this), 1e18);
        MockERC20(Currency.unwrap(key.currency0)).approve(address(modifyLiquidityRouter), 1e18);
        modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(0, 60, 1e18, 0), new bytes(111));
        assertEq(mockHooks.beforeAddLiquidityData(), new bytes(111));
        assertEq(mockHooks.afterAddLiquidityData(), new bytes(111));

        modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(0, 60, -1e18, 0), new bytes(222));
        assertEq(mockHooks.beforeRemoveLiquidityData(), new bytes(222));
        assertEq(mockHooks.afterRemoveLiquidityData(), new bytes(222));
    }

    function test_beforeAfterAddLiquidity_calledWithPositiveLiquidityDelta() external {
        MockERC20(Currency.unwrap(key.currency0)).mint(address(this), 1e18);
        MockERC20(Currency.unwrap(key.currency0)).approve(address(modifyLiquidityRouter), 1e18);
        modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(0, 60, 100, 0), new bytes(111));
        assertEq(mockHooks.beforeAddLiquidityData(), new bytes(111));
        assertEq(mockHooks.afterAddLiquidityData(), new bytes(111));
    }

    function test_beforeAfterRemoveLiquidity_calledWithZeroLiquidityDelta() external {
        MockERC20(Currency.unwrap(key.currency0)).mint(address(this), 1e18);
        MockERC20(Currency.unwrap(key.currency0)).approve(address(modifyLiquidityRouter), 1e18);
        modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(0, 60, 1e18, 0), new bytes(111));
        assertEq(mockHooks.beforeAddLiquidityData(), new bytes(111));
        assertEq(mockHooks.afterAddLiquidityData(), new bytes(111));

        modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(0, 60, 0, 0), new bytes(222));
        assertEq(mockHooks.beforeAddLiquidityData(), new bytes(111));
        assertEq(mockHooks.afterAddLiquidityData(), new bytes(111));
        assertEq(mockHooks.beforeRemoveLiquidityData(), new bytes(222));
        assertEq(mockHooks.afterRemoveLiquidityData(), new bytes(222));
    }

    function test_beforeAfterRemoveLiquidity_calledWithPositiveLiquidityDelta() external {
        modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(0, 60, 1e18, 0), new bytes(111));
        MockERC20(Currency.unwrap(key.currency0)).mint(address(this), 1e18);
        MockERC20(Currency.unwrap(key.currency0)).approve(address(modifyLiquidityRouter), 1e18);
        modifyLiquidityRouter.modifyLiquidity(key, IPoolManager.ModifyLiquidityParams(0, 60, -1e18, 0), new bytes(111));
        assertEq(mockHooks.beforeRemoveLiquidityData(), new bytes(111));
        assertEq(mockHooks.afterRemoveLiquidityData(), new bytes(111));
    }

    function test_beforeAddLiquidity_invalidReturn() external {
        mockHooks.setReturnValue(mockHooks.beforeAddLiquidity.selector, bytes4(0xdeadbeef));
        MockERC20(Currency.unwrap(key.currency0)).mint(address(this), 1e18);
        MockERC20(Currency.unwrap(key.currency0)).approve(address(modifyLiquidityRouter), 1e18);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
    }

    function test_beforeRemoveLiquidity_invalidReturn() external {
        mockHooks.setReturnValue(mockHooks.beforeRemoveLiquidity.selector, bytes4(0xdeadbeef));
        MockERC20(Currency.unwrap(key.currency0)).mint(address(this), 1e18);
        MockERC20(Currency.unwrap(key.currency0)).approve(address(modifyLiquidityRouter), 1e18);
        modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        modifyLiquidityRouter.modifyLiquidity(key, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);
    }

    function test_afterAddLiquidity_invalidReturn() external {
        mockHooks.setReturnValue(mockHooks.afterAddLiquidity.selector, bytes4(0xdeadbeef));
        MockERC20(Currency.unwrap(key.currency0)).mint(address(this), 1e18);
        MockERC20(Currency.unwrap(key.currency0)).approve(address(modifyLiquidityRouter), 1e18);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
    }

    function test_afterRemoveLiquidity_invalidReturn() external {
        mockHooks.setReturnValue(mockHooks.afterRemoveLiquidity.selector, bytes4(0xdeadbeef));
        MockERC20(Currency.unwrap(key.currency0)).mint(address(this), 1e18);
        MockERC20(Currency.unwrap(key.currency0)).approve(address(modifyLiquidityRouter), 1e18);
        modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        modifyLiquidityRouter.modifyLiquidity(key, REMOVE_LIQUIDITY_PARAMS, ZERO_BYTES);
    }

    function test_swap_succeedsWithHook() external {
        IPoolManager.SwapParams memory swapParams =
                            IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: SQRT_PRICE_1_2});

        PoolSwapTest.TestSettings memory testSettings =
                            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        swapRouter.swap(key, swapParams, testSettings, new bytes(222));
        assertEq(mockHooks.beforeSwapData(), new bytes(222));
        assertEq(mockHooks.afterSwapData(), new bytes(222));
    }

    function test_beforeSwap_invalidReturn() external {
        mockHooks.setReturnValue(mockHooks.beforeSwap.selector, bytes4(0xdeadbeef));
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        swapRouter.swap(
            key,
            IPoolManager.SwapParams(false, 100, SQRT_PRICE_1_1 + 60),
            PoolSwapTest.TestSettings(true, true),
            ZERO_BYTES
        );
    }

    function test_afterSwap_invalidReturn() external {
        mockHooks.setReturnValue(mockHooks.afterSwap.selector, bytes4(0xdeadbeef));
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        swapRouter.swap(
            key,
            IPoolManager.SwapParams(false, 100, SQRT_PRICE_1_1 + 60),
            PoolSwapTest.TestSettings(true, true),
            ZERO_BYTES
        );
    }

    function test_donate_succeedsWithHook() external {
        donateRouter.donate(key, 100, 200, new bytes(333));
        assertEq(mockHooks.beforeDonateData(), new bytes(333));
        assertEq(mockHooks.afterDonateData(), new bytes(333));
    }

    function test_beforeDonate_invalidReturn() external {
        mockHooks.setReturnValue(mockHooks.beforeDonate.selector, bytes4(0xdeadbeef));
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        donateRouter.donate(key, 100, 200, ZERO_BYTES);
    }

    function test_afterDonate_invalidReturn() external {
        mockHooks.setReturnValue(mockHooks.beforeDonate.selector, bytes4(0xdeadbeef));
        vm.expectRevert(Hooks.InvalidHookResponse.selector);
        donateRouter.donate(key, 100, 200, ZERO_BYTES);
    }
}

contract HooksUniTest is Test, GasSnapshot {
    using Hooks for IHooks;

    uint256 private hookPermissionCount = 14;
    uint256 private clearAllHookPermissionsMask = uint256(~uint160(0) >> (hookPermissionCount));

    // Test data
    IHooks private testHook = IHooks(address(1));
    bytes4 private testSelector = bytes4(0x00000002);
    int256 private testReturnValue = int256(3);
    bytes private testCallData = abi.encode(testSelector);
    bytes private testReturnData = abi.encode(testSelector, testReturnValue);
    uint160 private testSqrtPrice = 100;
    PoolKey private testKey;

    // hook validation
    function test_validateHookPermissions_noHooks(uint160 addr) external view {
        // Arrange
        Hooks.Permissions memory permissions;

        // Act & Assert
        _test_validateHookPermissions(addr, permissions);
    }


    function test_validateHookPermissions_beforeInitialize(uint160 addr) external view {
        // Arrange
        Hooks.Permissions memory permissions;
        permissions.beforeInitialize = true;

        // Act & Assert
        _test_validateHookPermissions(addr, permissions);
    }

    function test_validateHookPermissions_afterInitialize(uint160 addr) external view {
        // Arrange
        Hooks.Permissions memory permissions;
        permissions.afterInitialize = true;

        // Act & Assert
        _test_validateHookPermissions(addr, permissions);
    }

    function test_validateHookPermissions_beforeAndAfterInitialize(uint160 addr) external view {
        // Arrange
        Hooks.Permissions memory permissions;
        permissions.beforeInitialize = true;
        permissions.afterInitialize = true;

        // Act & Assert
        _test_validateHookPermissions(addr, permissions);
    }

    function test_validateHookPermissions_beforeAddLiquidity(uint160 addr) external view {
        // Arrange
        Hooks.Permissions memory permissions;
        permissions.beforeAddLiquidity = true;

        // Act & Assert
        _test_validateHookPermissions(addr, permissions);
    }

    function test_validateHookPermissions_afterAddLiquidity(uint160 addr) external view {
        // Arrange
        Hooks.Permissions memory permissions;
        permissions.afterAddLiquidity = true;

        // Act & Assert
        _test_validateHookPermissions(addr, permissions);
    }

    function test_validateHookPermissions_beforeAndAfterAddLiquidity(uint160 addr) external view {
        // Arrange
        Hooks.Permissions memory permissions;
        permissions.beforeAddLiquidity = true;
        permissions.afterAddLiquidity = true;

        // Act & Assert
        _test_validateHookPermissions(addr, permissions);
    }

    function test_validateHookPermissions_beforeRemoveLiquidity(uint160 addr) external view {
        // Arrange
        Hooks.Permissions memory permissions;
        permissions.beforeRemoveLiquidity = true;

        // Act & Assert
        _test_validateHookPermissions(addr, permissions);
    }

    function test_validateHookPermissions_afterRemoveLiquidity(uint160 addr) external view {
        // Arrange
        Hooks.Permissions memory permissions;
        permissions.afterRemoveLiquidity = true;

        // Act & Assert
        _test_validateHookPermissions(addr, permissions);
    }

    function test_validateHookPermissions_beforeAfterRemoveLiquidity(uint160 addr) external view {
        // Arrange
        Hooks.Permissions memory permissions;
        permissions.beforeRemoveLiquidity = true;
        permissions.afterRemoveLiquidity = true;

        // Act & Assert
        _test_validateHookPermissions(addr, permissions);
    }

    function test_validateHookPermissions_beforeInitializeAfterAddLiquidity(uint160 addr) external view {
        // Arrange
        Hooks.Permissions memory permissions;
        permissions.beforeInitialize = true;
        permissions.afterAddLiquidity = true;

        // Act & Assert
        _test_validateHookPermissions(addr, permissions);
    }

    function test_validateHookPermissions_beforeSwap(uint160 addr) external view {
        // Arrange
        Hooks.Permissions memory permissions;
        permissions.beforeSwap = true;

        // Act & Assert
        _test_validateHookPermissions(addr, permissions);
    }

    function test_validateHookPermissions_afterSwap(uint160 addr) external view {
        // Arrange
        Hooks.Permissions memory permissions;
        permissions.afterSwap = true;

        // Act & Assert
        _test_validateHookPermissions(addr, permissions);
    }

    function test_validateHookPermissions_beforeAndAfterSwap(uint160 addr) external view {
        // Arrange
        Hooks.Permissions memory permissions;
        permissions.beforeSwap = true;
        permissions.afterSwap = true;

        // Act & Assert
        _test_validateHookPermissions(addr, permissions);
    }

    function test_validateHookPermissions_beforeDonate(uint160 addr) external view {
        // Arrange
        Hooks.Permissions memory permissions;
        permissions.beforeDonate = true;

        // Act & Assert
        _test_validateHookPermissions(addr, permissions);
    }

    function test_validateHookPermissions_afterDonate(uint160 addr) external view {
        // Arrange
        Hooks.Permissions memory permissions;
        permissions.afterDonate = true;

        // Act & Assert
        _test_validateHookPermissions(addr, permissions);
    }

    function test_validateHookPermissions_beforeAndAfterDonate(uint160 addr) external view {
        // Arrange
        Hooks.Permissions memory permissions;
        permissions.beforeDonate = true;
        permissions.afterDonate = true;

        // Act & Assert
        _test_validateHookPermissions(addr, permissions);
    }

    function test_validateHookPermissions_allHooks(uint160 addr) external view {
        // Arrange
        Hooks.Permissions memory permissions;
        permissions.beforeInitialize = true;
        permissions.afterInitialize = true;
        permissions.beforeAddLiquidity = true;
        permissions.afterAddLiquidity = true;
        permissions.beforeRemoveLiquidity = true;
        permissions.afterRemoveLiquidity = true;
        permissions.beforeSwap = true;
        permissions.afterSwap = true;
        permissions.beforeDonate = true;
        permissions.afterDonate = true;
        permissions.beforeSwapReturnDelta = true;
        permissions.afterSwapReturnDelta = true;
        permissions.afterAddLiquidityReturnDelta = true;
        permissions.afterRemoveLiquidityReturnDelta = true;

        // Act & Assert
        _test_validateHookPermissions(addr, permissions);
    }

    function _test_validateHookPermissions(uint160 addr, Hooks.Permissions memory permissions) internal view {
        // Arrange
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermissionsMask);
        preAddr = permissions.beforeInitialize ? preAddr | uint160(Hooks.BEFORE_INITIALIZE_FLAG) : preAddr;
        preAddr = permissions.afterInitialize ? preAddr | uint160(Hooks.AFTER_INITIALIZE_FLAG) : preAddr;
        preAddr = permissions.beforeAddLiquidity ? preAddr | uint160(Hooks.BEFORE_ADD_LIQUIDITY_FLAG) : preAddr;
        preAddr = permissions.afterAddLiquidity ? preAddr | uint160(Hooks.AFTER_ADD_LIQUIDITY_FLAG) : preAddr;
        preAddr = permissions.beforeRemoveLiquidity ? preAddr | uint160(Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG) : preAddr;
        preAddr = permissions.afterRemoveLiquidity ? preAddr | uint160(Hooks.AFTER_REMOVE_LIQUIDITY_FLAG) : preAddr;
        preAddr = permissions.beforeSwap ? preAddr | uint160(Hooks.BEFORE_SWAP_FLAG) : preAddr;
        preAddr = permissions.afterSwap ? preAddr | uint160(Hooks.AFTER_SWAP_FLAG) : preAddr;
        preAddr = permissions.beforeDonate ? preAddr | uint160(Hooks.BEFORE_DONATE_FLAG) : preAddr;
        preAddr = permissions.afterDonate ? preAddr | uint160(Hooks.AFTER_DONATE_FLAG) : preAddr;
        preAddr = permissions.beforeSwapReturnDelta ? preAddr | uint160(Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG) : preAddr;
        preAddr = permissions.afterSwapReturnDelta ? preAddr | uint160(Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG) : preAddr;
        preAddr = permissions.afterAddLiquidityReturnDelta ? preAddr | uint160(Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG) : preAddr;
        preAddr = permissions.afterRemoveLiquidityReturnDelta ? preAddr | uint160(Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG) : preAddr;

        IHooks hookAddr = IHooks(address(preAddr));

        // Act
        Hooks.validateHookPermissions(hookAddr, permissions);

        // Assert
        assertEq(hookAddr.hasPermission(Hooks.BEFORE_INITIALIZE_FLAG), permissions.beforeInitialize);
        assertEq(hookAddr.hasPermission(Hooks.AFTER_INITIALIZE_FLAG), permissions.afterInitialize);
        assertEq(hookAddr.hasPermission(Hooks.BEFORE_ADD_LIQUIDITY_FLAG), permissions.beforeAddLiquidity);
        assertEq(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_FLAG), permissions.afterAddLiquidity);
        assertEq(hookAddr.hasPermission(Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG), permissions.beforeRemoveLiquidity);
        assertEq(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_FLAG), permissions.afterRemoveLiquidity);
        assertEq(hookAddr.hasPermission(Hooks.BEFORE_SWAP_FLAG), permissions.beforeSwap);
        assertEq(hookAddr.hasPermission(Hooks.AFTER_SWAP_FLAG), permissions.afterSwap);
        assertEq(hookAddr.hasPermission(Hooks.BEFORE_DONATE_FLAG), permissions.beforeDonate);
        assertEq(hookAddr.hasPermission(Hooks.AFTER_DONATE_FLAG), permissions.afterDonate);
        assertEq(hookAddr.hasPermission(Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG), permissions.beforeSwapReturnDelta);
        assertEq(hookAddr.hasPermission(Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG), permissions.afterSwapReturnDelta);
        assertEq(hookAddr.hasPermission(Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG), permissions.afterAddLiquidityReturnDelta);
        assertEq(hookAddr.hasPermission(Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG), permissions.afterRemoveLiquidityReturnDelta);
    }

    function test_validateHookPermissions_failsAllHooks(uint152 addr, uint16 mask) external {
        // Arrange
        uint160 preAddr = uint160(uint256(addr));
        mask = mask & 0xfffc; // the last 7 bits are all 0, we just want a 14 bit mask
        vm.assume(mask != 0xfffc); // we want any combination except all hooks
        IHooks hookAddr = IHooks(address(uint160(preAddr) | (uint160(mask) << 151)));
        Hooks.Permissions memory permissions;
        permissions.beforeInitialize = true;
        permissions.afterInitialize = true;
        permissions.beforeAddLiquidity = true;
        permissions.afterAddLiquidity = true;
        permissions.beforeRemoveLiquidity = true;
        permissions.afterRemoveLiquidity = true;
        permissions.beforeSwap = true;
        permissions.afterSwap = true;
        permissions.beforeDonate = true;
        permissions.afterDonate = true;
        permissions.beforeSwapReturnDelta = true;
        permissions.afterSwapReturnDelta = true;
        permissions.afterAddLiquidityReturnDelta = true;
        permissions.afterRemoveLiquidityReturnDelta = true;

        // Expect
        vm.expectRevert(abi.encodeWithSelector(Hooks.HookAddressNotValid.selector, (address(hookAddr))));

        // Act
        Hooks.validateHookPermissions(hookAddr, permissions);
    }

    function test_validateHookPermissions_failsNoHooks(uint160 addr, uint16 mask) external {
        // Arrange
        uint160 preAddr = addr & uint160(0x007ffffFfffffffffFffffFFfFFFFFFffFFfFFff);
        mask = mask & 0xfffc; // the last 7 bits are all 0, we just want a 14 bit mask
        vm.assume(mask != 0); // we want any combination except no hooks
        IHooks hookAddr = IHooks(address(preAddr | (uint160(mask) << 144)));
        Hooks.Permissions memory permissions;

        // Expect
        vm.expectRevert(abi.encodeWithSelector(Hooks.HookAddressNotValid.selector, (address(hookAddr))));

        // Act
        Hooks.validateHookPermissions(hookAddr, permissions);
    }

    function test_isValidHookAddress_valid_anyFlags() external pure {
        _test_isValidHookAddress_valid(uint160(0x8000000000000000000000000000000000000000), 3000);
        _test_isValidHookAddress_valid(uint160(0x4000000000000000000000000000000000000000), 3000);
        _test_isValidHookAddress_valid(uint160(0x2000000000000000000000000000000000000000), 3000);
        _test_isValidHookAddress_valid(uint160(0x1000000000000000000000000000000000000000), 3000);
        _test_isValidHookAddress_valid(uint160(0x0800000000000000000000000000000000000000), 3000);
        _test_isValidHookAddress_valid(uint160(0x0400000000000000000000000000000000000000), 3000);
        _test_isValidHookAddress_valid(uint160(0x0200000000000000000000000000000000000000), 3000);
        _test_isValidHookAddress_valid(uint160(0x0100000000000000000000000000000000000000), 3000);
        _test_isValidHookAddress_valid(uint160(0x0080000000000000000000000000000000000000), 3000);
        _test_isValidHookAddress_valid(uint160(0x0040000000000000000000000000000000000000), 3000);
        _test_isValidHookAddress_valid(uint160(0xf00040A85D5af5bf1d1762f925BDAddc4201f984), 3000);
    }

    function testIsValidHookAddress_valid_zeroAddressFixedFee() external pure {
        _test_isValidHookAddress_valid(0, 3000);
    }

    function test_isValidHookAddress_valid_noFlagsWithDynamicFee() external pure {
        _test_isValidHookAddress_valid(uint160(0x0000000000000000000000000000000000000001), LPFeeLibrary.DYNAMIC_FEE_FLAG);
        _test_isValidHookAddress_valid(uint160(0x0000000000000000000000000000000000000001), LPFeeLibrary.DYNAMIC_FEE_FLAG | uint24(3000));
        _test_isValidHookAddress_valid(uint160(0x8000000000000000000000000000000000000000), 3000);
    }

    function _test_isValidHookAddress_valid(uint160 _hook, uint24 _fee) internal pure {
        // Arrange
        IHooks hookAddr = IHooks(address(_hook));

        // Act
        bool isValid = Hooks.isValidHookAddress(hookAddr, _fee);

        // Assert
        assertTrue(isValid);
    }

    function testIsValidHookAddress_invalid_zeroAddressWithDynamicFee() external pure {
        _test_isValidHookAddress_invalid(0, LPFeeLibrary.DYNAMIC_FEE_FLAG);
    }

    function testIsValidHookAddress_invalid_returnsDeltaWithoutHookFlag(uint160 addr) external view {
        uint160 preAddr = uint160(uint256(addr) & clearAllHookPermissionsMask);
        _test_isValidHookAddress_invalid(uint160(preAddr | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG), 3000);
        _test_isValidHookAddress_invalid(uint160(preAddr | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG), 3000);
        _test_isValidHookAddress_invalid(uint160(preAddr | Hooks.AFTER_ADD_LIQUIDITY_RETURNS_DELTA_FLAG), 3000);
        _test_isValidHookAddress_invalid(uint160(preAddr | Hooks.AFTER_REMOVE_LIQUIDITY_RETURNS_DELTA_FLAG), 3000);
    }

    function test_isValidHookAddress_invalid_noFlagsNoDynamicFee() external pure {
        _test_isValidHookAddress_invalid(uint160(0x0000000000000000000000000000000000000001), 3000);
        _test_isValidHookAddress_invalid(uint160(0x0001000000000000000000000000000000000001), 3000);
        _test_isValidHookAddress_invalid(uint160(0x000340A85D5AF5bf1D1762F925BdaddC4201f984), 3000);
    }

    function _test_isValidHookAddress_invalid(uint160 _hook, uint24 _fee) internal pure {
        // Arrange
        IHooks hookAddr = IHooks(address(_hook));

        // Act
        bool isValid = Hooks.isValidHookAddress(hookAddr, _fee);

        // Assert
        assertFalse(isValid);
    }

    function test_gas_hasPermission() external {
        snapStart("HooksShouldCallBeforeSwap");
        IHooks(address(0)).hasPermission(Hooks.BEFORE_SWAP_FLAG);
        snapEnd();
    }

    function test_callHook() external {
        // Act
        vm.mockCall(address(testHook), testCallData, testReturnData);
        bytes memory result = testHook.callHook(testCallData);

        // Assert
        assertEq(result, testReturnData);
    }
    
    function test_callHook_revert() external {
        vm.skip(true);

        // Expect
        vm.expectRevert(testReturnData);

        // Act
        vm.mockCallRevert(address(testHook), testCallData, testReturnData);
        testHook.callHook(testCallData);
    }
    
    function test_callHook_revertsIfInvalidHookResponse() external {
        vm.skip(true);

        // Arrange
        bytes memory data = hex"deadbeef";

        // Expect
        vm.expectRevert(Hooks.InvalidHookResponse.selector);

        // Act
        vm.mockCall(address(testHook), data, testReturnData);
        testHook.callHook(data);
    }

    function test_callHookWithReturnDelta_withParsing() external {
        // Act
        vm.mockCall(address(testHook), testCallData, testReturnData);
        int256 delta = testHook.callHookWithReturnDelta(testCallData, true);

        // Assert
        assertEq(delta, testReturnValue);
    }

    function test_callHookWithReturnDelta_withoutParsing() external {
        // Act
        vm.mockCall(address(testHook), testCallData, testReturnData);
        int256 delta = testHook.callHookWithReturnDelta(testCallData, false);

        // Assert
        assertEq(delta, 0);
    }
}