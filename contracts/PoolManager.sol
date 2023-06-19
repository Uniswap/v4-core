// SPDX-License-Identifier: BUSL-1.1
// 中文注释由 WTF Academy 贡献
pragma solidity ^0.8.19;

import {Hooks} from "./libraries/Hooks.sol";
import {Pool} from "./libraries/Pool.sol";
import {SafeCast} from "./libraries/SafeCast.sol";
import {Position} from "./libraries/Position.sol";
import {Currency, CurrencyLibrary} from "./libraries/CurrencyLibrary.sol";

import {NoDelegateCall} from "./NoDelegateCall.sol";
import {Owned} from "./Owned.sol";
import {IHooks} from "./interfaces/IHooks.sol";
import {IProtocolFeeController} from "./interfaces/IProtocolFeeController.sol";
import {IDynamicFeeManager} from "./interfaces/IDynamicFeeManager.sol";
import {IHookFeeManager} from "./interfaces/IHookFeeManager.sol";
import {IPoolManager} from "./interfaces/IPoolManager.sol";
import {ILockCallback} from "./interfaces/callback/ILockCallback.sol";
import {Fees} from "./libraries/Fees.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {PoolId, PoolIdLibrary} from "./libraries/PoolId.sol";
import {BalanceDelta} from "./types/BalanceDelta.sol";

/// @notice 保管所有池子的状态
contract PoolManager is IPoolManager, Owned, NoDelegateCall, ERC1155, IERC1155Receiver {
    /* ============ 库 ============ */
    using PoolIdLibrary for PoolKey;
    using SafeCast for *;
    using Pool for *;
    using Hooks for IHooks;
    using Position for mapping(bytes32 => Position.Info);
    using CurrencyLibrary for Currency;
    using Fees for uint24;

    /* ============ 状态变量 ============ */
    /// @notice 返回已初始化池子键的最大tickSpacing常量
    int24 public constant override MAX_TICK_SPACING = type(int16).max;

    /// @notice 返回协议费用的最小分母，将其限制为最大25%
    uint8 public constant MIN_PROTOCOL_FEE_DENOMINATOR = 4;

    /// @notice 返回已初始化池子键的最小tickSpacing常量
    int24 public constant override MIN_TICK_SPACING = 1;

    /// @notice 记录所有池子状态
    mapping(PoolId id => Pool.State) public pools;
    /// @notice 记录protocol fee
    mapping(Currency currency => uint256) public override protocolFeesAccrued;
    /// @notice 记录hook fee
    mapping(address hookAddress => mapping(Currency currency => uint256)) public hookFeesAccrued;

    IProtocolFeeController public protocolFeeController;

    uint256 private immutable controllerGasLimit;
    
    /* ============ 函数 ============ */
    // 构造器
    constructor(uint256 _controllerGasLimit) ERC1155("") {
        controllerGasLimit = _controllerGasLimit;
    }

    /* ============ view 函数 ============ */
    /// @notice 通过PoolKey查询池子状态
    function _getPool(PoolKey memory key) private view returns (Pool.State storage) {
        return pools[key.toId()];
    }

    /// @notice 获取给定池子的slot0的当前值
    function getSlot0(PoolId id)
        external
        view
        override
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint8 protocolSwapFee,
            uint8 protocolWithdrawFee,
            uint8 hookSwapFee,
            uint8 hookWithdrawFee
        )
    {
        Pool.Slot0 memory slot0 = pools[id].slot0;

        return (
            slot0.sqrtPriceX96,
            slot0.tick,
            slot0.protocolSwapFee,
            slot0.protocolWithdrawFee,
            slot0.hookSwapFee,
            slot0.hookWithdrawFee
        );
    }

    /// @notice 获取给定池子的当前流动性值
    function getLiquidity(PoolId id) external view override returns (uint128 liquidity) {
        return pools[id].liquidity;
    }

    /// @notice 获取指定池子和持仓的当前流动性值
    function getLiquidity(PoolId id, address owner, int24 tickLower, int24 tickUpper)
        external
        view
        override
        returns (uint128 liquidity)
    {
        return pools[id].positions.get(owner, tickLower, tickUpper).liquidity;
    }

    /* ============ 初始化池子相关函数 ============ */
    /// @notice 初始化给定池子ID的状态
    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external override returns (int24 tick) {
        if (key.fee & Fees.STATIC_FEE_MASK >= 1000000) revert FeeTooLarge();

        // 检查tick spacing可能溢出的情况，具体参考 TickBitmap.sol 
        if (key.tickSpacing > MAX_TICK_SPACING) revert TickSpacingTooLarge();
        if (key.tickSpacing < MIN_TICK_SPACING) revert TickSpacingTooSmall();
        if (!key.hooks.isValidHookAddress(key.fee)) revert Hooks.HookAddressNotValid(address(key.hooks));

        // 调用 BeforeInitialize hook
        if (key.hooks.shouldCallBeforeInitialize()) {
            if (key.hooks.beforeInitialize(msg.sender, key, sqrtPriceX96) != IHooks.beforeInitialize.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }

        // 初始化池子
        PoolId id = key.toId();
        (uint8 protocolSwapFee, uint8 protocolWithdrawFee) = _fetchProtocolFees(key);
        (uint8 hookSwapFee, uint8 hookWithdrawFee) = _fetchHookFees(key);
        tick = pools[id].initialize(sqrtPriceX96, protocolSwapFee, hookSwapFee, protocolWithdrawFee, hookWithdrawFee);

        // 调用 AfterInitialize hook
        if (key.hooks.shouldCallAfterInitialize()) {
            if (key.hooks.afterInitialize(msg.sender, key, sqrtPriceX96, tick) != IHooks.afterInitialize.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }

        // 释放Initialize事件
        emit Initialize(id, key.currency0, key.currency1, key.fee, key.tickSpacing, key.hooks);
    }

    /* ============ Lock相关函数 ============ */
    /// @notice 返回给定ERC20货币的储备
    mapping(Currency currency => uint256) public override reservesOf;

    /// @notice 表示锁定池子的地址堆栈。每次调用#lock都会将地址推送到堆栈上
    /// @param index 锁定者的索引，也称为锁定者的ID
    address[] public override lockedBy;

    /// @notice 获取lockedBy数组的长度
    function lockedByLength() external view returns (uint256) {
        return lockedBy.length;
    }

    /// @notice Lock 状态 struct
    /// @member nonzeroDeltaCount 非零值的 currencyDelta 映射条目的数量
    /// @member currencyDelta 记录应付给 locker（正数）或应付给池（负数）的货币金额
    struct LockState {
        uint256 nonzeroDeltaCount;
        mapping(Currency => int256) currencyDelta;
    }

    /// @dev 表示给定索引处的 locker 的状态。每个 locker 在释放锁之前必须拥有净 0 的欠款。注意，此处为 private，因为无法将嵌套的映射公开为公共变量。
    mapping(uint256 => LockState) private lockStates;

    /// @notice 返回给定locker ID的非零delta计数
    /// @param id locker的ID
    function getNonzeroDeltaCount(uint256 id) external view returns (uint256) {
        return lockStates[id].nonzeroDeltaCount;
    }

    /// @notice 获取给定locker ID的特定货币的当前delta值和其在currencies touched数组中的位置
    /// @param id locker的ID
    /// @param currency 要查找delta的货币
    function getCurrencyDelta(uint256 id, Currency currency) external view returns (int256) {
        return lockStates[id].currencyDelta[currency];
    }

    /// @notice 所有操作都通过此函数进行
    /// @param data 通过`ILockCallback(msg.sender).lockCallback(data)`传递给回调函数的任何数据
    /// @return 调用`ILockCallback(msg.sender).lockCallback(data)`返回的数据
    function lock(bytes calldata data) external override returns (bytes memory result) {
        // 将msg.sender添加到locker中
        uint256 id = lockedBy.length;
        lockedBy.push(msg.sender);

        // 调用者在此回调函数中完成所有操作，包括通过调用 settle 支付所欠的款项
        result = ILockCallback(msg.sender).lockAcquired(id, data);

        // 检查delta是否都为0
        unchecked {
            LockState storage lockState = lockStates[id];
            if (lockState.nonzeroDeltaCount != 0) revert CurrencyNotSettled();
        }

        // 将msg.sender从locker中删除
        lockedBy.pop();
    }

    /// @dev 累积对单个货币余额变化的映射 
    function _accountDelta(Currency currency, int128 delta) internal {
        if (delta == 0) return;
        // 获取当前lock状态
        LockState storage lockState = lockStates[lockedBy.length - 1];
        // 获取当前delta
        int256 current = lockState.currencyDelta[currency];
        // 计算delta
        int256 next = current + delta;
        // 更新nonzeroDeltaCount
        unchecked {
            if (next == 0) {
                lockState.nonzeroDeltaCount--;
            } else if (current == 0) {
                lockState.nonzeroDeltaCount++;
            }
        }
        // 更新currencyDelta
        lockState.currencyDelta[currency] = next;
    }

    /// @dev 累积对货币余额变化的映射
    function _accountPoolBalanceDelta(PoolKey memory key, BalanceDelta delta) internal {
        _accountDelta(key.currency0, delta.amount0());
        _accountDelta(key.currency1, delta.amount1());
    }

    /// @dev 修饰器，只能被locker调用
    modifier onlyByLocker() {
        address locker = lockedBy[lockedBy.length - 1];
        if (msg.sender != locker) revert LockedBy(locker);
        _;
    }

    /* ============ 修改LP持仓相关函数 ============ */
    /// @notice 修改给定池子的持仓
    function modifyPosition(PoolKey memory key, IPoolManager.ModifyPositionParams memory params)
        external
        override
        noDelegateCall
        onlyByLocker
        returns (BalanceDelta delta)
    {
        // 调用BeforeModifyPosition hook
        if (key.hooks.shouldCallBeforeModifyPosition()) {
            if (key.hooks.beforeModifyPosition(msg.sender, key, params) != IHooks.beforeModifyPosition.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }

        // 获取池子fee和delta
        PoolId id = key.toId();
        Pool.Fees memory fees;
        (delta, fees) = pools[id].modifyPosition(
            Pool.ModifyPositionParams({
                owner: msg.sender,
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                liquidityDelta: params.liquidityDelta.toInt128(),
                tickSpacing: key.tickSpacing
            })
        );

        // 更新delta
        _accountPoolBalanceDelta(key, delta);

        // 更新Fee相关变量
        unchecked {
            if (fees.feeForProtocol0 > 0) {
                protocolFeesAccrued[key.currency0] += fees.feeForProtocol0;
            }
            if (fees.feeForProtocol1 > 0) {
                protocolFeesAccrued[key.currency1] += fees.feeForProtocol1;
            }
            if (fees.feeForHook0 > 0) {
                hookFeesAccrued[address(key.hooks)][key.currency0] += fees.feeForHook0;
            }
            if (fees.feeForHook1 > 0) {
                hookFeesAccrued[address(key.hooks)][key.currency1] += fees.feeForHook1;
            }
        }

        // 调用AfterModifyPosition hook
        if (key.hooks.shouldCallAfterModifyPosition()) {
            if (key.hooks.afterModifyPosition(msg.sender, key, params, delta) != IHooks.afterModifyPosition.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }
        // 释放ModifyPosition事件
        emit ModifyPosition(id, msg.sender, params.tickLower, params.tickUpper, params.liquidityDelta);
    }

    /* ============ Swap相关函数 ============ */
    /// @notice 对给定池子进行兑换
    function swap(PoolKey memory key, IPoolManager.SwapParams memory params)
        external
        override
        noDelegateCall
        onlyByLocker
        returns (BalanceDelta delta)
    {
        // 调用CallBeforeSwap hook
        if (key.hooks.shouldCallBeforeSwap()) {
            if (key.hooks.beforeSwap(msg.sender, key, params) != IHooks.beforeSwap.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }

        // 设置总的交换手续费，可以通过钩子函数设置或作为初始化时的静态手续费
        uint24 totalSwapFee;
        if (key.fee.isDynamicFee()) {
            // 动态手续费
            totalSwapFee = IDynamicFeeManager(address(key.hooks)).getFee(key);
            if (totalSwapFee >= 1000000) revert FeeTooLarge();
        } else {
            // 清除前四位，因为它们可能被用于钩子手续费
            totalSwapFee = key.fee & Fees.STATIC_FEE_MASK;
        }

        // 调用Pool的swap函数执行swap
        uint256 feeForProtocol;
        uint256 feeForHook;
        Pool.SwapState memory state;
        PoolId id = key.toId();
        (delta, feeForProtocol, feeForHook, state) = pools[id].swap(
            Pool.SwapParams({
                fee: totalSwapFee,
                tickSpacing: key.tickSpacing,
                zeroForOne: params.zeroForOne,
                amountSpecified: params.amountSpecified,
                sqrtPriceLimitX96: params.sqrtPriceLimitX96
            })
        );

        // 更新delta
        _accountPoolBalanceDelta(key, delta);

        // 对input货币收取手续费
        unchecked {
            if (feeForProtocol > 0) {
                protocolFeesAccrued[params.zeroForOne ? key.currency0 : key.currency1] += feeForProtocol;
            }
            if (feeForHook > 0) {
                hookFeesAccrued[address(key.hooks)][params.zeroForOne ? key.currency0 : key.currency1] += feeForHook;
            }
        }

        // 调用CallAfterSwap hook
        if (key.hooks.shouldCallAfterSwap()) {
            if (key.hooks.afterSwap(msg.sender, key, params, delta) != IHooks.afterSwap.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }

        // 释放Swap事件
        emit Swap(
            id,
            msg.sender,
            delta.amount0(),
            delta.amount1(),
            state.sqrtPriceX96,
            state.liquidity,
            state.tick,
            totalSwapFee
        );
    }

    /// @notice 将指定货币金额捐赠给具有给定池子键的池子
    function donate(PoolKey memory key, uint256 amount0, uint256 amount1)
        external
        override
        noDelegateCall
        onlyByLocker
        returns (BalanceDelta delta)
    {
        // 调用CallBeforeDonate hook
        if (key.hooks.shouldCallBeforeDonate()) {
            if (key.hooks.beforeDonate(msg.sender, key, amount0, amount1) != IHooks.beforeDonate.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }

        // 执行donate
        delta = _getPool(key).donate(amount0, amount1);

        // 更新delta
        _accountPoolBalanceDelta(key, delta);
        
        // 调用CallAfterDonate hook
        if (key.hooks.shouldCallAfterDonate()) {
            if (key.hooks.afterDonate(msg.sender, key, amount0, amount1) != IHooks.afterDonate.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }
    }

    /// @notice 用户调用以结算池子对用户所欠的一些值
    /// @dev 也可用作“免费”闪电贷款的机制
    function take(Currency currency, address to, uint256 amount) external override noDelegateCall onlyByLocker {
        // 更新delta
        _accountDelta(currency, amount.toInt128());
        // 更新余额
        reservesOf[currency] -= amount;
        // 转账
        currency.transfer(to, amount);
    }

    /// @notice 用户调用以将值转移至ERC1155余额
    function mint(Currency currency, address to, uint256 amount) external override noDelegateCall onlyByLocker {
        // 更新delta
        _accountDelta(currency, amount.toInt128());
        // mint erc1155
        _mint(to, currency.toId(), amount, "");
    }

    /// @notice 用户调用以支付所欠款
    function settle(Currency currency) external payable override noDelegateCall onlyByLocker returns (uint256 paid) {
        // 更新 reserve
        uint256 reservesBefore = reservesOf[currency];
        reservesOf[currency] = currency.balanceOfSelf();
        paid = reservesOf[currency] - reservesBefore;
        // 更新delta
        // 这里的减法必须安全
        _accountDelta(currency, -(paid.toInt128()));
    }

    /// @notice 销毁erc1155，并更新delta
    function _burnAndAccount(Currency currency, uint256 amount) internal {
        _burn(address(this), currency.toId(), amount);
        _accountDelta(currency, -(amount.toInt128()));
    }

    /// @notice 回调函数，在接收ERC1155代币转账时被调用
    function onERC1155Received(address, address, uint256 id, uint256 value, bytes calldata) external returns (bytes4) {
        if (msg.sender != address(this)) revert NotPoolManagerToken();
        _burnAndAccount(CurrencyLibrary.fromId(id), value);
        return IERC1155Receiver.onERC1155Received.selector;
    }

    /// @notice 回调函数，在接收ERC1155代币批量转账时被调用
    function onERC1155BatchReceived(address, address, uint256[] calldata ids, uint256[] calldata values, bytes calldata)
        external
        returns (bytes4)
    {
        if (msg.sender != address(this)) revert NotPoolManagerToken();
        // unchecked to save gas on incrementations of i
        unchecked {
            for (uint256 i; i < ids.length; i++) {
                _burnAndAccount(CurrencyLibrary.fromId(ids[i]), values[i]);
            }
        }
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function setProtocolFeeController(IProtocolFeeController controller) external onlyOwner {
        protocolFeeController = controller;
        emit ProtocolFeeControllerUpdated(address(controller));
    }

    function setProtocolFees(PoolKey memory key) external {
        (uint8 newProtocolSwapFee, uint8 newProtocolWithdrawFee) = _fetchProtocolFees(key);
        PoolId id = key.toId();
        pools[id].setProtocolFees(newProtocolSwapFee, newProtocolWithdrawFee);
        emit ProtocolFeeUpdated(id, newProtocolSwapFee, newProtocolWithdrawFee);
    }

    function _fetchProtocolFees(PoolKey memory key)
        internal
        view
        returns (uint8 protocolSwapFee, uint8 protocolWithdrawFee)
    {
        if (address(protocolFeeController) != address(0)) {
            // note that EIP-150 mandates that calls requesting more than 63/64ths of remaining gas
            // will be allotted no more than this amount, so controllerGasLimit must be set with this
            // in mind.
            if (gasleft() < controllerGasLimit) revert ProtocolFeeCannotBeFetched();
            try protocolFeeController.protocolFeesForPool{gas: controllerGasLimit}(key) returns (
                uint8 updatedProtocolSwapFee, uint8 updatedProtocolWithdrawFee
            ) {
                protocolSwapFee = updatedProtocolSwapFee;
                protocolWithdrawFee = updatedProtocolWithdrawFee;
            } catch {}

            _checkProtocolFee(protocolSwapFee);
            _checkProtocolFee(protocolWithdrawFee);
        }
    }

    function _checkProtocolFee(uint8 fee) internal pure {
        if (fee != 0) {
            uint8 fee0 = fee % 16;
            uint8 fee1 = fee >> 4;
            // The fee is specified as a denominator so it cannot be LESS than the MIN_PROTOCOL_FEE_DENOMINATOR (unless it is 0).
            if (
                (fee0 != 0 && fee0 < MIN_PROTOCOL_FEE_DENOMINATOR) || (fee1 != 0 && fee1 < MIN_PROTOCOL_FEE_DENOMINATOR)
            ) {
                revert FeeTooLarge();
            }
        }
    }

    function setHookFees(PoolKey memory key) external {
        (uint8 newHookSwapFee, uint8 newHookWithdrawFee) = _fetchHookFees(key);
        PoolId id = key.toId();
        pools[id].setHookFees(newHookSwapFee, newHookWithdrawFee);
        emit HookFeeUpdated(id, newHookSwapFee, newHookWithdrawFee);
    }

    /// @notice There is no cap on the hook fee, but it is specified as a percentage taken on the amount after the protocol fee is applied, if there is a protocol fee.
    function _fetchHookFees(PoolKey memory key) internal view returns (uint8 hookSwapFee, uint8 hookWithdrawFee) {
        if (key.fee.hasHookSwapFee()) {
            hookSwapFee = IHookFeeManager(address(key.hooks)).getHookSwapFee(key);
        }

        if (key.fee.hasHookWithdrawFee()) {
            hookWithdrawFee = IHookFeeManager(address(key.hooks)).getHookWithdrawFee(key);
        }
    }

    function collectProtocolFees(address recipient, Currency currency, uint256 amount)
        external
        returns (uint256 amountCollected)
    {
        if (msg.sender != owner && msg.sender != address(protocolFeeController)) revert InvalidCaller();

        amountCollected = (amount == 0) ? protocolFeesAccrued[currency] : amount;
        protocolFeesAccrued[currency] -= amountCollected;
        currency.transfer(recipient, amountCollected);
    }

    function collectHookFees(address recipient, Currency currency, uint256 amount)
        external
        returns (uint256 amountCollected)
    {
        address hookAddress = msg.sender;

        amountCollected = (amount == 0) ? hookFeesAccrued[hookAddress][currency] : amount;
        recipient = (recipient == address(0)) ? hookAddress : recipient;

        hookFeesAccrued[hookAddress][currency] -= amountCollected;
        currency.transfer(recipient, amountCollected);
    }

    /// @notice 外部合约调用以访问细粒度的池子状态
    /// @param slot 要sload的槽的键
    /// @return value 作为bytes32的槽的值
    function extsload(bytes32 slot) external view returns (bytes32 value) {
        /// @solidity memory-safe-assembly
        assembly {
            value := sload(slot)
        }
    }

    /// @notice 外部合约调用以访问细粒度的池子状态
    /// @param slot 要开始sload的槽的键
    /// @param nSlots 要加载到返回值中的槽的数量
    /// @return value 作为动态字节数组连接的sload的槽的值
    function extsload(bytes32 startSlot, uint256 nSlots) external view returns (bytes memory) {
        bytes memory value = new bytes(32 * nSlots);

        /// @solidity memory-safe-assembly
        assembly {
            for { let i := 0 } lt(i, nSlots) { i := add(i, 1) } {
                mstore(add(value, mul(add(i, 1), 32)), sload(add(startSlot, i)))
            }
        }

        return value;
    }

    /// @notice receive native tokens for native pools
    receive() external payable {}
}
