// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Hooks} from "./libraries/Hooks.sol";
import {Pool} from "./libraries/Pool.sol";
import {SafeCast} from "./libraries/SafeCast.sol";
import {Position} from "./libraries/Position.sol";
import {Currency, CurrencyLibrary} from "./libraries/CurrencyLibrary.sol";

import {NoDelegateCall} from "./NoDelegateCall.sol";
import {IHooks} from "./interfaces/IHooks.sol";

import {IDynamicFeeManager} from "./interfaces/IDynamicFeeManager.sol";
import {IHookFeeManager} from "./interfaces/IHookFeeManager.sol";
import {IPoolManager} from "./interfaces/IPoolManager.sol";
import {ILockCallback} from "./interfaces/callback/ILockCallback.sol";
import {Fees} from "./libraries/Fees.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {PoolId, PoolIdLibrary} from "./libraries/PoolId.sol";
import {BalanceDelta} from "./types/BalanceDelta.sol";

/// @notice Holds the state for all pools
contract PoolManager is IPoolManager, NoDelegateCall, ERC1155, IERC1155Receiver {
    using PoolIdLibrary for PoolKey;
    using SafeCast for *;
    using Pool for *;
    using Hooks for IHooks;
    using Position for mapping(bytes32 => Position.Info);
    using CurrencyLibrary for Currency;
    using Fees for uint24;

    /// @inheritdoc IPoolManager
    int24 public constant override MAX_TICK_SPACING = type(int16).max;

    /// @inheritdoc IPoolManager
    uint8 public constant override MIN_PROTOCOL_FEE_DENOMINATOR = 4;

    /// @inheritdoc IPoolManager
    int24 public constant override MIN_TICK_SPACING = 1;

    uint256 private immutable controllerGasLimit;

    address public protocolFeeController;

    address[] public lockedBy;

    /// @member nonzeroDeltaCount The number of entries in the currencyDelta mapping that have a non-zero value
    /// @member currencyDelta The amount owed to the locker (positive) or owed to the pool (negative) of the currency
    struct LockState {
        uint256 nonzeroDeltaCount;
        mapping(Currency currency => int256) currencyDelta;
    }

    /// @dev Represents the state of the locker at the given index. Each locker must have net 0 currencies owed before
    /// releasing their lock. Note this is private because the nested mappings cannot be exposed as a public variable.
    mapping(uint256 index => LockState) private lockStates;

    /// @inheritdoc IPoolManager
    mapping(Currency currency => uint256) public override reservesOf;

    mapping(PoolId id => Pool.State) public pools;

    mapping(address hookAddress => mapping(Currency currency => uint256)) public hookFeesAccrued;

    constructor(uint256 _controllerGasLimit) ERC1155("") {
        controllerGasLimit = _controllerGasLimit;
    }

    function _getPool(PoolKey memory key) private view returns (Pool.State storage) {
        return pools[key.toId()];
    }

    /// @inheritdoc IPoolManager
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

    /// @inheritdoc IPoolManager
    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external override returns (int24 tick) {
        if (key.fee & Fees.STATIC_FEE_MASK >= 1000000) revert FeeTooLarge();

        // see TickBitmap.sol for overflow conditions that can arise from tick spacing being too large
        if (key.tickSpacing > MAX_TICK_SPACING) revert TickSpacingTooLarge();
        if (key.tickSpacing < MIN_TICK_SPACING) revert TickSpacingTooSmall();
        if (!key.hooks.isValidHookAddress(key.fee)) revert Hooks.HookAddressNotValid(address(key.hooks));

        if (key.hooks.shouldCallBeforeInitialize()) {
            if (key.hooks.beforeInitialize(msg.sender, key, sqrtPriceX96) != IHooks.beforeInitialize.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }

        PoolId id = key.toId();
        uint8 protocolSwapFee = 0;
        uint8 protocolWithdrawFee = 0;
        (uint8 hookSwapFee, uint8 hookWithdrawFee) = _fetchHookFees(key);
        tick = pools[id].initialize(sqrtPriceX96, protocolSwapFee, hookSwapFee, protocolWithdrawFee, hookWithdrawFee);

        if (key.hooks.shouldCallAfterInitialize()) {
            if (key.hooks.afterInitialize(msg.sender, key, sqrtPriceX96, tick) != IHooks.afterInitialize.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }
    }

    /// @inheritdoc IPoolManager
    function getNonzeroDeltaCount(uint256 id) external view returns (uint256) {
        return lockStates[id].nonzeroDeltaCount;
    }

    /// @inheritdoc IPoolManager
    function getCurrencyDelta(uint256 id, Currency currency) external view returns (int256) {
        return lockStates[id].currencyDelta[currency];
    }

    /// @inheritdoc IPoolManager
    function lock(bytes calldata data) external override returns (bytes memory result) {
        uint256 id = lockedBy.length;
        lockedBy.push(msg.sender);

        // the caller does everything in this callback, including paying what they owe via calls to settle
        result = ILockCallback(msg.sender).lockAcquired(id, data);

        unchecked {
            LockState storage lockState = lockStates[id];
            if (lockState.nonzeroDeltaCount != 0) revert CurrencyNotSettled();
        }

        lockedBy.pop();
    }

    function _accountDelta(Currency currency, int128 delta) internal {
        if (delta == 0) return;

        LockState storage lockState = lockStates[lockedBy.length - 1];
        int256 current = lockState.currencyDelta[currency];

        int256 next = current + delta;
        unchecked {
            if (next == 0) {
                lockState.nonzeroDeltaCount--;
            } else if (current == 0) {
                lockState.nonzeroDeltaCount++;
            }
        }

        lockState.currencyDelta[currency] = next;
    }

    /// @dev Accumulates a balance change to a map of currency to balance changes
    function _accountPoolBalanceDelta(PoolKey memory key, BalanceDelta delta) internal {
        _accountDelta(key.currency0, delta.amount0());
        _accountDelta(key.currency1, delta.amount1());
    }

    modifier onlyByLocker() {
        address locker = lockedBy[lockedBy.length - 1];
        if (msg.sender != locker) revert LockedBy(locker);
        _;
    }

    /// @inheritdoc IPoolManager
    function modifyPosition(PoolKey memory key, IPoolManager.ModifyPositionParams memory params)
        external
        override
        noDelegateCall
        onlyByLocker
        returns (BalanceDelta delta)
    {
        if (key.hooks.shouldCallBeforeModifyPosition()) {
            if (key.hooks.beforeModifyPosition(msg.sender, key, params) != IHooks.beforeModifyPosition.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }

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

        _accountPoolBalanceDelta(key, delta);

        unchecked {
            if (fees.feeForHook0 > 0) {
                hookFeesAccrued[address(key.hooks)][key.currency0] += fees.feeForHook0;
            }
            if (fees.feeForHook1 > 0) {
                hookFeesAccrued[address(key.hooks)][key.currency1] += fees.feeForHook1;
            }
        }

        if (key.hooks.shouldCallAfterModifyPosition()) {
            if (key.hooks.afterModifyPosition(msg.sender, key, params, delta) != IHooks.afterModifyPosition.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }
    }

    /// @inheritdoc IPoolManager
    function swap(PoolKey memory key, IPoolManager.SwapParams memory params)
        external
        override
        noDelegateCall
        onlyByLocker
        returns (BalanceDelta delta)
    {
        if (key.hooks.shouldCallBeforeSwap()) {
            if (key.hooks.beforeSwap(msg.sender, key, params) != IHooks.beforeSwap.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }

        // Set the total swap fee, either through the hook or as the static fee set an initialization.
        uint24 totalSwapFee;
        if (key.fee.isDynamicFee()) {
            totalSwapFee = IDynamicFeeManager(address(key.hooks)).getFee(key);
            if (totalSwapFee >= 1000000) revert FeeTooLarge();
        } else {
            // clear the top 4 bits since they may be flagged for hook fees
            totalSwapFee = key.fee & Fees.STATIC_FEE_MASK;
        }

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

        _accountPoolBalanceDelta(key, delta);
        // the fee is on the input currency

        unchecked {
            if (feeForHook > 0) {
                hookFeesAccrued[address(key.hooks)][params.zeroForOne ? key.currency0 : key.currency1] += feeForHook;
            }
        }

        if (key.hooks.shouldCallAfterSwap()) {
            if (key.hooks.afterSwap(msg.sender, key, params, delta) != IHooks.afterSwap.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }
    }

    /// @inheritdoc IPoolManager
    function donate(PoolKey memory key, uint256 amount0, uint256 amount1)
        external
        override
        noDelegateCall
        onlyByLocker
        returns (BalanceDelta delta)
    {
        if (key.hooks.shouldCallBeforeDonate()) {
            if (key.hooks.beforeDonate(msg.sender, key, amount0, amount1) != IHooks.beforeDonate.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }

        delta = _getPool(key).donate(amount0, amount1);

        _accountPoolBalanceDelta(key, delta);

        if (key.hooks.shouldCallAfterDonate()) {
            if (key.hooks.afterDonate(msg.sender, key, amount0, amount1) != IHooks.afterDonate.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }
    }

    /// @inheritdoc IPoolManager
    function take(Currency currency, address to, uint256 amount) external override noDelegateCall onlyByLocker {
        _accountDelta(currency, amount.toInt128());
        reservesOf[currency] -= amount;
        currency.transfer(to, amount);
    }

    /// @inheritdoc IPoolManager
    function mint(Currency currency, address to, uint256 amount) external override noDelegateCall onlyByLocker {
        _accountDelta(currency, amount.toInt128());
        _mint(to, currency.toId(), amount, "");
    }

    /// @inheritdoc IPoolManager
    function settle(Currency currency) external payable override noDelegateCall onlyByLocker returns (uint256 paid) {
        uint256 reservesBefore = reservesOf[currency];
        reservesOf[currency] = currency.balanceOfSelf();
        paid = reservesOf[currency] - reservesBefore;
        // subtraction must be safe
        _accountDelta(currency, -(paid.toInt128()));
    }

    function _burnAndAccount(Currency currency, uint256 amount) internal {
        _burn(address(this), currency.toId(), amount);
        _accountDelta(currency, -(amount.toInt128()));
    }

    function onERC1155Received(address, address, uint256 id, uint256 value, bytes calldata) external returns (bytes4) {
        if (msg.sender != address(this)) revert NotPoolManagerToken();
        _burnAndAccount(CurrencyLibrary.fromId(id), value);
        return IERC1155Receiver.onERC1155Received.selector;
    }

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

    function setHookFees(PoolKey memory key) external {
        (uint8 newHookSwapFee, uint8 newHookWithdrawFee) = _fetchHookFees(key);
        PoolId id = key.toId();
        pools[id].setHookFees(newHookSwapFee, newHookWithdrawFee);
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

    function collectHookFees(address recipient, Currency currency, uint256 amount)
        external
        returns (uint256 amountCollected)
    {
        amountCollected = (amount == 0) ? hookFeesAccrued[msg.sender][currency] : amount;
        recipient = (recipient == address(0)) ? msg.sender : recipient;

        hookFeesAccrued[msg.sender][currency] -= amountCollected;
        currency.transfer(recipient, amountCollected);
    }

    /// @notice receive native tokens for native pools
    receive() external payable {}
}
