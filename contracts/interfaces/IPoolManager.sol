// SPDX-License-Identifier: GPL-2.0-or-later
// 中文注释由 WTF Academy 贡献
pragma solidity ^0.8.19;

import {Currency} from "../libraries/CurrencyLibrary.sol";
import {Pool} from "../libraries/Pool.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IHooks} from "./IHooks.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {PoolId} from "../libraries/PoolId.sol";

interface IPoolManager is IERC1155 {
    /// @notice 当涉及的货币超过最大值256时抛出异常
    error MaxCurrenciesTouched();

    /// @notice 当提供的燃料不足以查找协议费用时抛出异常
    error ProtocolFeeCannotBeFetched();

    /// @notice 当锁定后未净额结算货币时抛出异常
    error CurrencyNotSettled();

    /// @notice 当被调用的函数的地址不是当前锁定者时抛出异常
    /// @param locker 当前锁定者地址
    error LockedBy(address locker);

    /// @notice 存款的 ERC1155 不是 Uniswap ERC1155
    error NotPoolManagerToken();

    /// @notice 池子必须具有小于100%的费用，在#initialize和动态费用池中强制执行
    error FeeTooLarge();

    /// @notice 池子的tickSpacing在#initialize中受到type(int16).max的限制，以防止溢出
    error TickSpacingTooLarge();
    /// @notice 池子在#initialize中必须具有正的非零tickSpacing
    error TickSpacingTooSmall();

    /// @notice 初始化新池子时触发的事件
    /// @param id 新池子的池子键的abi编码哈希
    /// @param currency0 池子中的第一种货币，按地址排序
    /// @param currency1 池子中的第二种货币，按地址排序
    /// @param fee 池子中每次交换收取的费用，以百分之一的bip记
    /// @param tickSpacing 初始化的ticks之间的最小数量
    /// @param hooks 池子的hooks合约地址，如果没有则为address(0)
    event Initialize(
        PoolId indexed id,
        Currency indexed currency0,
        Currency indexed currency1,
        uint24 fee,
        int24 tickSpacing,
        IHooks hooks
    );

    /// @notice 修改流动性持仓时触发的事件
    /// @param id 被修改的池子的PoolKey的abi编码哈希
    /// @param sender 修改池子的地址
    /// @param tickLower 持仓的较低tick
    /// @param tickUpper 持仓的较高tick
    /// @param liquidityDelta 增加或减少的流动性数量
    event ModifyPosition(
        PoolId indexed id, address indexed sender, int24 tickLower, int24 tickUpper, int256 liquidityDelta
    );

    /// @notice 在货币0和货币1之间进行兑换时触发的事件
    /// @param id 被修改的池子的池子键的abi编码哈希
    /// @param sender 启动兑换调用并接收回调的地址
    /// @param amount0 池子中货币0余额的变化量
    /// @param amount1 池子中货币1余额的变化量
    /// @param sqrtPriceX96 兑换后池子的sqrt(价格)，以Q64.96表示
    /// @param liquidity 兑换后池子的流动性
    /// @param tick 兑换后池子价格的log base 1.0001
    event Swap(
        PoolId indexed id,
        address indexed sender,
        int128 amount0,
        int128 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick,
        uint24 fee
    );

    event ProtocolFeeUpdated(PoolId indexed id, uint8 protocolSwapFee, uint8 protocolWithdrawFee);

    event ProtocolFeeControllerUpdated(address protocolFeeController);

    event HookFeeUpdated(PoolId indexed id, uint8 hookSwapFee, uint8 hookWithdrawFee);

    /// @notice 返回用于标识池子的键
    struct PoolKey {
        /// @notice 池子的较低货币，按数字顺序排序
        Currency currency0;
        /// @notice 池子的较高货币，按数字顺序排序
        Currency currency1;
        /// @notice 池子的交换费用，上限为1_000_000。最高4位确定hook是否设置了任何费用。
        uint24 fee;
        /// @notice 涉及持仓的ticks必须是tick间距的倍数
        int24 tickSpacing;
        /// @notice 池子的hooks
        IHooks hooks;
    }

    /// @notice 返回已初始化池子键的最大tickSpacing常量
    function MAX_TICK_SPACING() external view returns (int24);

    /// @notice 返回已初始化池子键的最小tickSpacing常量
    function MIN_TICK_SPACING() external view returns (int24);

    /// @notice 返回协议费用的最小分母，将其限制为最大25%
    function MIN_PROTOCOL_FEE_DENOMINATOR() external view returns (uint8);

    /// @notice 获取给定池子的slot0的当前值
    function getSlot0(PoolId id)
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint8 protocolSwapFee,
            uint8 protocolWithdrawFee,
            uint8 hookSwapFee,
            uint8 hookWithdrawFee
        );

    /// @notice 获取给定池子的当前流动性值
    function getLiquidity(PoolId id) external view returns (uint128 liquidity);

    /// @notice 获取指定池子和持仓的当前流动性值
    function getLiquidity(PoolId id, address owner, int24 tickLower, int24 tickUpper)
        external
        view
        returns (uint128 liquidity);

    // @notice 给定货币地址，返回在该货币中应计提的协议费用
    function protocolFeesAccrued(Currency) external view returns (uint256);

    /// @notice 返回给定ERC20货币的储备
    function reservesOf(Currency currency) external view returns (uint256);

    /// @notice 初始化给定池子ID的状态
    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external returns (int24 tick);

    /// @notice 表示锁定池子的地址堆栈。每次调用#lock都会将地址推送到堆栈上
    /// @param index 锁定者的索引，也称为锁定者的ID
    function lockedBy(uint256 index) external view returns (address);

    /// @notice 获取lockedBy数组的长度
    function lockedByLength() external view returns (uint256);

    /// @notice 返回给定locker ID的非零delta计数
    /// @param id locker的ID
    function getNonzeroDeltaCount(uint256 id) external view returns (uint256);

    /// @notice 获取给定locker ID的特定货币的当前delta值和其在currencies touched数组中的位置
    /// @param id locker的ID
    /// @param currency 要查找delta的货币
    function getCurrencyDelta(uint256 id, Currency currency) external view returns (int256);

    /// @notice 所有操作都通过此函数进行
    /// @param data 通过`ILockCallback(msg.sender).lockCallback(data)`传递给回调函数的任何数据
    /// @return 调用`ILockCallback(msg.sender).lockCallback(data)`返回的数据
    function lock(bytes calldata data) external returns (bytes memory);

    struct ModifyPositionParams {
        // 持仓的较低tick和较高tick
        int24 tickLower;
        int24 tickUpper;
        // 修改流动性的方式
        int256 liquidityDelta;
    }

    /// @notice 修改给定池子的持仓
    function modifyPosition(PoolKey memory key, ModifyPositionParams memory params) external returns (BalanceDelta);

    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice 对给定池子进行兑换
    function swap(PoolKey memory key, SwapParams memory params) external returns (BalanceDelta);

    /// @notice 将指定货币金额捐赠给具有给定池子键的池子
    function donate(PoolKey memory key, uint256 amount0, uint256 amount1) external returns (BalanceDelta);

    /// @notice 用户调用以结算池子对用户所欠的一些值
    /// @dev 也可用作“免费”闪电贷款的机制
    function take(Currency currency, address to, uint256 amount) external;

    /// @notice 用户调用以将值转移至ERC1155余额
    function mint(Currency token, address to, uint256 amount) external;

    /// @notice 用户调用以支付所欠款
    function settle(Currency token) external payable returns (uint256 paid);

    /// @notice 设置给定池子的协议交换和提现费用
    /// 协议费用始终是欠费的一部分。如果底层费用为0，则不会产生任何协议费用，即使设置为>0。
    function setProtocolFees(PoolKey memory key) external;

    /// @notice 设置给定池子hook的交换和提现费用
    function setHookFees(PoolKey memory key) external;

    /// @notice 外部合约调用以访问细粒度的池子状态
    /// @param slot 要sload的槽的键
    /// @return value 作为bytes32的槽的值
    function extsload(bytes32 slot) external view returns (bytes32 value);

    /// @notice 外部合约调用以访问细粒度的池子状态
    /// @param slot 要开始sload的槽的键
    /// @param nSlots 要加载到返回值中的槽的数量
    /// @return value 作为动态字节数组连接的sload的槽的值
    function extsload(bytes32 slot, uint256 nSlots) external view returns (bytes memory value);
}