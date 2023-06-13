// SPDX-License-Identifier: BUSL-1.1
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
import {PoolId} from "./libraries/PoolId.sol";
import {BalanceDelta} from "./types/BalanceDelta.sol";

/// @notice Holds the state for all pools
contract PoolManager is IPoolManager, Owned, NoDelegateCall, ERC1155, IERC1155Receiver {
    using PoolId for PoolKey;
    using SafeCast for *;
    using Pool for *;
    using Hooks for IHooks;
    using Position for mapping(bytes32 => Position.Info);
    using CurrencyLibrary for Currency;
    using Fees for uint24;

    /// @inheritdoc IPoolManager
    int24 public constant override MAX_TICK_SPACING = type(int16).max;

    /// @inheritdoc IPoolManager
    uint8 public constant MIN_PROTOCOL_FEE_DENOMINATOR = 4;

    /// @inheritdoc IPoolManager
    int24 public constant override MIN_TICK_SPACING = 1;

    mapping(bytes32 poolId => Pool.State) public pools;

    mapping(Currency currency => uint256) public override protocolFeesAccrued;

    mapping(address hookAddress => mapping(Currency currency => uint256)) public hookFeesAccrued;

    IProtocolFeeController public protocolFeeController;

    uint256 private immutable controllerGasLimit;

    constructor(uint256 _controllerGasLimit) ERC1155("") {
        controllerGasLimit = _controllerGasLimit;
    }

    function _getPool(PoolKey memory key) private view returns (Pool.State storage) {
        return pools[key.toId()];
    }

    /// @inheritdoc IPoolManager
    function getSlot0(bytes32 poolId)
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
        Pool.Slot0 memory slot0 = pools[poolId].slot0;

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
    function getLiquidity(bytes32 poolId) external view override returns (uint128 liquidity) {
        return pools[poolId].liquidity;
    }

    /// @inheritdoc IPoolManager
    function getLiquidity(bytes32 poolId, address owner, int24 tickLower, int24 tickUpper)
        external
        view
        override
        returns (uint128 liquidity)
    {
        return pools[poolId].positions.get(owner, tickLower, tickUpper).liquidity;
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

        bytes32 poolId = key.toId();
        (uint8 protocolSwapFee, uint8 protocolWithdrawFee) = _fetchProtocolFees(key);
        (uint8 hookSwapFee, uint8 hookWithdrawFee) = _fetchHookFees(key);
        tick =
            pools[poolId].initialize(sqrtPriceX96, protocolSwapFee, hookSwapFee, protocolWithdrawFee, hookWithdrawFee);

        if (key.hooks.shouldCallAfterInitialize()) {
            if (key.hooks.afterInitialize(msg.sender, key, sqrtPriceX96, tick) != IHooks.afterInitialize.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }

        emit Initialize(poolId, key.currency0, key.currency1, key.fee, key.tickSpacing, key.hooks);
    }

    /// @inheritdoc IPoolManager
    mapping(Currency currency => uint256) public override reservesOf;

    /// @inheritdoc IPoolManager
    address[] public override lockedBy;

    /// @inheritdoc IPoolManager
    function lockedByLength() external view returns (uint256) {
        return lockedBy.length;
    }

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

        bytes32 poolId = key.toId();
        Pool.Fees memory fees;
        (delta, fees) = pools[poolId].modifyPosition(
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

        if (key.hooks.shouldCallAfterModifyPosition()) {
            if (key.hooks.afterModifyPosition(msg.sender, key, params, delta) != IHooks.afterModifyPosition.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }

        emit ModifyPosition(poolId, msg.sender, params.tickLower, params.tickUpper, params.liquidityDelta);
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
        bytes32 poolId = key.toId();
        (delta, feeForProtocol, feeForHook, state) = pools[poolId].swap(
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
            if (feeForProtocol > 0) {
                protocolFeesAccrued[params.zeroForOne ? key.currency0 : key.currency1] += feeForProtocol;
            }
            if (feeForHook > 0) {
                hookFeesAccrued[address(key.hooks)][params.zeroForOne ? key.currency0 : key.currency1] += feeForHook;
            }
        }

        if (key.hooks.shouldCallAfterSwap()) {
            if (key.hooks.afterSwap(msg.sender, key, params, delta) != IHooks.afterSwap.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }

        emit Swap(
            poolId,
            msg.sender,
            delta.amount0(),
            delta.amount1(),
            state.sqrtPriceX96,
            state.liquidity,
            state.tick,
            totalSwapFee
        );
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

    function setProtocolFeeController(IProtocolFeeController controller) external onlyOwner {
        protocolFeeController = controller;
        emit ProtocolFeeControllerUpdated(address(controller));
    }

    function setProtocolFees(PoolKey memory key) external {
        (uint8 newProtocolSwapFee, uint8 newProtocolWithdrawFee) = _fetchProtocolFees(key);
        bytes32 poolId = key.toId();
        pools[poolId].setProtocolFees(newProtocolSwapFee, newProtocolWithdrawFee);
        emit ProtocolFeeUpdated(poolId, newProtocolSwapFee, newProtocolWithdrawFee);
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
        bytes32 poolId = key.toId();
        pools[poolId].setHookFees(newHookSwapFee, newHookWithdrawFee);
        emit HookFeeUpdated(poolId, newHookSwapFee, newHookWithdrawFee);
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

    function extsload(bytes32 slot) external view returns (bytes32 value) {
        /// @solidity memory-safe-assembly
        assembly {
            value := sload(slot)
        }
    }

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
