// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {ERC1155} from '@openzeppelin/contracts/token/ERC1155/ERC1155.sol';
import {IERC1155Receiver} from '@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol';
import {ReentrancyGuard} from '@openzeppelin/contracts/security/ReentrancyGuard.sol';

import {Hooks} from './libraries/Hooks.sol';
import {Pool} from './libraries/Pool.sol';
import {SafeCast} from './libraries/SafeCast.sol';
import {Position} from './libraries/Position.sol';
import {Currency, CurrencyLibrary} from './libraries/CurrencyLibrary.sol';
import {CurrencyDelta, CurrencyDeltaMapping} from './libraries/CurrencyDelta.sol';

import {NoDelegateCall} from './NoDelegateCall.sol';
import {Owned} from './Owned.sol';
import {IHooks} from './interfaces/IHooks.sol';
import {IProtocolFeeController} from './interfaces/IProtocolFeeController.sol';
import {IPoolManager} from './interfaces/IPoolManager.sol';
import {IExecuteCallback} from './interfaces/callback/IExecuteCallback.sol';

import {PoolId} from './libraries/PoolId.sol';

/// @notice Holds the state for all pools
contract PoolManager is IPoolManager, Owned, NoDelegateCall, ERC1155, IERC1155Receiver, ReentrancyGuard {
    using PoolId for PoolKey;
    using SafeCast for *;
    using Pool for *;
    using Hooks for IHooks;
    using Position for mapping(bytes32 => Position.Info);
    using CurrencyLibrary for Currency;
    using CurrencyDeltaMapping for CurrencyDelta[];

    /// @inheritdoc IPoolManager
    int24 public constant override MAX_TICK_SPACING = type(int16).max;

    /// @inheritdoc IPoolManager
    int24 public constant override MIN_TICK_SPACING = 1;

    mapping(bytes32 => Pool.State) public pools;

    mapping(Currency => uint256) public override protocolFeesAccrued;
    IProtocolFeeController public protocolFeeController;

    /// @inheritdoc IPoolManager
    mapping(Currency => uint256) public override reservesOf;

    uint256 private immutable controllerGasLimit;

    constructor(uint256 _controllerGasLimit) ERC1155('') {
        controllerGasLimit = _controllerGasLimit;
    }

    function _getPool(PoolKey memory key) private view returns (Pool.State storage) {
        return pools[key.toId()];
    }

    /// @inheritdoc IPoolManager
    function getSlot0(bytes32 id)
        external
        view
        override
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint8 protocolFee
        )
    {
        Pool.Slot0 memory slot0 = pools[id].slot0;

        return (slot0.sqrtPriceX96, slot0.tick, slot0.protocolFee);
    }

    /// @inheritdoc IPoolManager
    function getLiquidity(bytes32 id) external view override returns (uint128 liquidity) {
        return pools[id].liquidity;
    }

    /// @inheritdoc IPoolManager
    function getLiquidity(
        bytes32 id,
        address owner,
        int24 tickLower,
        int24 tickUpper
    ) external view override returns (uint128 liquidity) {
        return pools[id].positions.get(owner, tickLower, tickUpper).liquidity;
    }

    /// @inheritdoc IPoolManager
    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external override returns (int24 tick) {
        // see TickBitmap.sol for overflow conditions that can arise from tick spacing being too large
        if (key.tickSpacing > MAX_TICK_SPACING) revert TickSpacingTooLarge();
        if (key.tickSpacing < MIN_TICK_SPACING) revert TickSpacingTooSmall();
        if (!key.hooks.isValidHookAddress()) revert Hooks.HookAddressNotValid(address(key.hooks));

        if (key.hooks.shouldCallBeforeInitialize()) {
            if (key.hooks.beforeInitialize(msg.sender, key, sqrtPriceX96) != IHooks.beforeInitialize.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }

        bytes32 id = key.toId();
        tick = pools[id].initialize(sqrtPriceX96, fetchPoolProtocolFee(key));

        if (key.hooks.shouldCallAfterInitialize()) {
            if (key.hooks.afterInitialize(msg.sender, key, sqrtPriceX96, tick) != IHooks.afterInitialize.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }

        emit Initialize(id, key.currency0, key.currency1, key.fee, key.tickSpacing, key.hooks);
    }

    function execute(
        bytes calldata operations,
        bytes[] calldata inputs,
        bytes calldata callbackData
    ) external nonReentrant returns (bytes memory result) {
        CurrencyDelta[] memory deltas;
        for (uint256 i = 0; i < operations.length; i++) {
            IPoolManager.Command command = IPoolManager.Command(uint8(operations[i]));
            if (command == IPoolManager.Command.SWAP) {
                (PoolKey memory key, IPoolManager.SwapParams memory params) = abi.decode(
                    inputs[i],
                    (PoolKey, IPoolManager.SwapParams)
                );
                IPoolManager.BalanceDelta memory delta = swap(key, params);
                _accountPoolBalanceDelta(deltas, key, delta);
            } else if (command == IPoolManager.Command.MODIFY) {
                (PoolKey memory key, IPoolManager.ModifyPositionParams memory params) = abi.decode(
                    inputs[i],
                    (PoolKey, IPoolManager.ModifyPositionParams)
                );
                IPoolManager.BalanceDelta memory delta = modifyPosition(key, params);
                _accountPoolBalanceDelta(deltas, key, delta);
            } else if (command == IPoolManager.Command.DONATE) {
                (PoolKey memory key, uint256 amount0, uint256 amount1) = abi.decode(
                    inputs[i],
                    (PoolKey, uint256, uint256)
                );
                IPoolManager.BalanceDelta memory delta = donate(key, amount0, amount1);
                _accountPoolBalanceDelta(deltas, key, delta);
            } else if (command == IPoolManager.Command.TAKE) {
                (Currency currency, address to, uint256 amount) = abi.decode(inputs[i], (Currency, address, uint256));
                if (amount == 0) {
                    amount = uint256(-deltas.get(currency));
                }
                take(currency, to, amount);
                deltas.add(currency, amount.toInt256());
            } else if (command == IPoolManager.Command.MINT) {
                (Currency currency, address to, uint256 amount) = abi.decode(inputs[i], (Currency, address, uint256));
                mint(currency, to, amount);
                deltas.add(currency, amount.toInt256());
            } else if (command == IPoolManager.Command.BURN) {
                (Currency currency, address from, uint256 amount) = abi.decode(inputs[i], (Currency, address, uint256));
                burn(currency, from, amount);
                deltas.add(currency, -(amount.toInt256()));
            } else {
                revert('Invalid command');
            }
        }

        // callback for payment
        result = IExecuteCallback(msg.sender).executeCallback(deltas, callbackData);

        for (uint256 i = 0; i < deltas.length; i++) {
            CurrencyDelta memory delta = deltas[i];
            uint256 paid = settle(delta.currency);
            if (delta.delta - paid.toInt256() != int256(0)) {
                revert CurrencyNotSettled();
            }
        }
    }

    /// @dev Accumulates a balance change to a map of currency to balance changes
    function _accountPoolBalanceDelta(
        CurrencyDelta[] memory deltas,
        PoolKey memory key,
        IPoolManager.BalanceDelta memory delta
    ) internal {
        deltas.add(key.currency0, delta.amount0);
        deltas.add(key.currency1, delta.amount1);
    }

    /// @notice modify liquidity position in the given pool
    function modifyPosition(PoolKey memory key, IPoolManager.ModifyPositionParams memory params)
        internal
        returns (IPoolManager.BalanceDelta memory delta)
    {
        if (key.hooks.shouldCallBeforeModifyPosition()) {
            if (key.hooks.beforeModifyPosition(msg.sender, key, params) != IHooks.beforeModifyPosition.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }

        bytes32 poolId = key.toId();
        delta = pools[poolId].modifyPosition(
            Pool.ModifyPositionParams({
                owner: msg.sender,
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                liquidityDelta: params.liquidityDelta.toInt128(),
                tickSpacing: key.tickSpacing
            })
        );

        if (key.hooks.shouldCallAfterModifyPosition()) {
            if (key.hooks.afterModifyPosition(msg.sender, key, params, delta) != IHooks.afterModifyPosition.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }

        emit ModifyPosition(poolId, msg.sender, params.tickLower, params.tickUpper, params.liquidityDelta);
    }

    /// @notice perform a swap on the given pool
    function swap(PoolKey memory key, IPoolManager.SwapParams memory params)
        internal
        returns (IPoolManager.BalanceDelta memory delta)
    {
        if (key.hooks.shouldCallBeforeSwap()) {
            if (key.hooks.beforeSwap(msg.sender, key, params) != IHooks.beforeSwap.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }

        uint256 feeForProtocol;
        Pool.SwapState memory state;
        bytes32 poolId = key.toId();
        (delta, feeForProtocol, state) = pools[poolId].swap(
            Pool.SwapParams({
                fee: key.fee,
                tickSpacing: key.tickSpacing,
                zeroForOne: params.zeroForOne,
                amountSpecified: params.amountSpecified,
                sqrtPriceLimitX96: params.sqrtPriceLimitX96
            })
        );

        // the fee is on the input currency
        unchecked {
            if (feeForProtocol > 0) {
                protocolFeesAccrued[params.zeroForOne ? key.currency0 : key.currency1] += feeForProtocol;
            }
        }

        if (key.hooks.shouldCallAfterSwap()) {
            if (key.hooks.afterSwap(msg.sender, key, params, delta) != IHooks.afterSwap.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }

        emit Swap(poolId, msg.sender, delta.amount0, delta.amount1, state.sqrtPriceX96, state.liquidity, state.tick);
    }

    /// @notice donate funds to the given pool
    function donate(
        PoolKey memory key,
        uint256 amount0,
        uint256 amount1
    ) internal returns (IPoolManager.BalanceDelta memory delta) {
        if (key.hooks.shouldCallBeforeDonate()) {
            if (key.hooks.beforeDonate(msg.sender, key, amount0, amount1) != IHooks.beforeDonate.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }

        delta = _getPool(key).donate(amount0, amount1);

        if (key.hooks.shouldCallAfterDonate()) {
            if (key.hooks.afterDonate(msg.sender, key, amount0, amount1) != IHooks.afterDonate.selector) {
                revert Hooks.InvalidHookResponse();
            }
        }
    }

    /// @notice take funds from the given pool
    function take(
        Currency currency,
        address to,
        uint256 amount
    ) internal {
        reservesOf[currency] -= amount;
        currency.transfer(to, amount);
    }

    /// @notice mint a claim to pool tokens
    function mint(
        Currency currency,
        address to,
        uint256 amount
    ) internal {
        _mint(to, currency.toId(), amount, '');
    }

    /// @notice burn a claim to pool tokens
    function burn(
        Currency currency,
        address from,
        uint256 amount
    ) internal {
        require(from == msg.sender || isApprovedForAll(from, msg.sender), 'ERC1155: caller is not owner nor approved');
        _burn(from, currency.toId(), amount);
    }

    /// @notice settle a pool by checking for received funds
    function settle(Currency currency) internal returns (uint256 paid) {
        uint256 reservesBefore = reservesOf[currency];
        reservesOf[currency] = currency.balanceOfSelf();
        paid = reservesOf[currency] - reservesBefore;
    }

    function onERC1155Received(
        address,
        address,
        uint256 id,
        uint256 value,
        bytes calldata
    ) external returns (bytes4) {
        // can't account for deltas outside of execute
        revert('not implemented');
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata
    ) external returns (bytes4) {
        revert('not implemented');
    }

    function setProtocolFeeController(IProtocolFeeController controller) external onlyOwner {
        protocolFeeController = controller;
        emit ProtocolFeeControllerUpdated(address(controller));
    }

    function setPoolProtocolFee(PoolKey memory key) external {
        uint8 newProtocolFee = fetchPoolProtocolFee(key);

        _getPool(key).setProtocolFee(newProtocolFee);
        emit ProtocolFeeUpdated(key.toId(), newProtocolFee);
    }

    function fetchPoolProtocolFee(PoolKey memory key) internal view returns (uint8 protocolFee) {
        if (address(protocolFeeController) != address(0)) {
            // note that EIP-150 mandates that calls requesting more than 63/64ths of remaining gas
            // will be allotted no more than this amount, so controllerGasLimit must be set with this
            // in mind.
            if (gasleft() < controllerGasLimit) revert ProtocolFeeCannotBeFetched();
            try protocolFeeController.protocolFeeForPool{gas: controllerGasLimit}(key) returns (
                uint8 updatedProtocolFee
            ) {
                protocolFee = updatedProtocolFee;
            } catch {}
        }
    }

    function collectProtocolFees(
        address recipient,
        Currency currency,
        uint256 amount
    ) external returns (uint256) {
        if (msg.sender != owner && msg.sender != address(protocolFeeController)) revert InvalidCaller();

        amount = (amount == 0) ? protocolFeesAccrued[currency] : amount;
        protocolFeesAccrued[currency] -= amount;
        currency.transfer(recipient, amount);

        return amount;
    }

    /// @notice receive native tokens for native pools
    receive() external payable {}
}
