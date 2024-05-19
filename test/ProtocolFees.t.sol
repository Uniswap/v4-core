// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {IERC20Minimal} from "src/interfaces/external/IERC20Minimal.sol";
import {ProtocolFees} from "src/ProtocolFees.sol";
import {IProtocolFees} from "src/interfaces/IProtocolFees.sol";
import {IProtocolFeeController} from "src/interfaces/IProtocolFeeController.sol";
import {Pool} from "src/libraries/Pool.sol";
import {PoolId, PoolIdLibrary} from "src/types/PoolId.sol";
import {PoolKey} from "src/types/PoolKey.sol";
import {ProtocolFeeLibrary} from "src/libraries/ProtocolFeeLibrary.sol";
import {Currency} from "src/types/Currency.sol";

contract ProtocolFeesTest is Test, GasSnapshot, ProtocolFees {
    using ProtocolFeeLibrary for uint24;
    using PoolIdLibrary for PoolKey;

    constructor() ProtocolFees(500000) {}

    IProtocolFees private self;
    PoolKey private key;

    function setUp() external {
        transferOwnership(address(this));
        self = IProtocolFees(address(this));
        protocolFeeController = IProtocolFeeController(address(0xabc));
        Pool.State storage pool = _getPool(key.toId());
        pool.slot0.sqrtPriceX96 = 1; // Initialize pool
    }

    /////////////////////////////////////////////////////
    ///////////// setProtocolFeeController //////////////
    /////////////////////////////////////////////////////

    function test_setProtocolFeeController() external {
        // Arrange
        IProtocolFeeController newFeeController = IProtocolFeeController(address(1));

        // Expect
        vm.expectEmit(false, false, false, true, address(self));
        emit ProtocolFeeControllerUpdated(address(newFeeController));

        // Act
        self.setProtocolFeeController(newFeeController);

        // Assert
        assertEq(address(protocolFeeController), address(newFeeController));
    }

    function test_setProtocolFeeController_failsIfNotOwner() external {
        // Arrange
        address originalFeeController = address(protocolFeeController);
        IProtocolFeeController newFeeController = IProtocolFeeController(address(1));

        // Expect
        vm.expectRevert("UNAUTHORIZED");

        // Act
        vm.prank(address(2)); // not the owner address
        self.setProtocolFeeController(newFeeController);

        // Assert
        assertEq(address(protocolFeeController), originalFeeController);
    }

    /////////////////////////////////////////////////////
    ////////////////// setProtocolFee ///////////////////
    /////////////////////////////////////////////////////

    function test_setProtocolFee() external {
        _test_setProtocolFee(_calculateProtocolFee(0, 0));
        _test_setProtocolFee(_calculateProtocolFee(0, 1000));
        _test_setProtocolFee(_calculateProtocolFee(1000, 0));
        _test_setProtocolFee(_calculateProtocolFee(1000, 1000));
    }

    function test_setProtocolFee_failsWithInvalidFee() external {
        _test_setProtocolFee_failsWithInvalidFee(_calculateProtocolFee(1001, 1000));
        _test_setProtocolFee_failsWithInvalidFee(_calculateProtocolFee(1000, 1001));
        _test_setProtocolFee_failsWithInvalidFee(_calculateProtocolFee(1001, 1001));
    }

    function test_setProtocolFee_failsWithInvalidCaller() external {
        // Expect
        vm.expectRevert(InvalidCaller.selector);

        // Act
        self.setProtocolFee(key, _calculateProtocolFee(1000, 1000));

        // Assert
        uint24 slot0ProtocolFee = _getPool(key.toId()).slot0.protocolFee;
        assertEq(slot0ProtocolFee, 0);
    }

    function _test_setProtocolFee(uint24 protocolFee) internal {
        // Expect
        vm.expectEmit(false, false, false, true);
        emit IProtocolFees.ProtocolFeeUpdated(key.toId(), protocolFee);

        // Act
        vm.prank(address(protocolFeeController));
        self.setProtocolFee(key, protocolFee);

        // Assert
        uint24 slot0ProtocolFee = _getPool(key.toId()).slot0.protocolFee;
        assertEq(slot0ProtocolFee, protocolFee);
    }

    function _test_setProtocolFee_failsWithInvalidFee(uint24 protocolFee) internal {
        // Expect
        vm.expectRevert(InvalidProtocolFee.selector);

        // Act
        vm.prank(address(protocolFeeController));
        self.setProtocolFee(key, protocolFee);

        // Assert
        uint24 slot0ProtocolFee = _getPool(key.toId()).slot0.protocolFee;
        assertEq(slot0ProtocolFee, 0);
    }

    /////////////////////////////////////////////////////
    //////////////// collectProtocolFees ////////////////
    /////////////////////////////////////////////////////

    function test_collectProtocolFees() external {
        // Arrange
        Currency currency = Currency.wrap(address(1));
        address recipient = address(2);
        uint256 feeAmount = 20;
        protocolFeesAccrued[currency] = feeAmount;

        // Act
        vm.mockCall(Currency.unwrap(currency), abi.encodeWithSelector(IERC20Minimal.transfer.selector, recipient, feeAmount / 2), abi.encode(true));
        vm.prank(address(protocolFeeController));
        self.collectProtocolFees(recipient, currency, feeAmount / 2);

        // Assert
        assertEq(protocolFeesAccrued[currency], feeAmount / 2);
    }

    function test_collectProtocolFees_allFees() external {
        // Arrange
        Currency currency = Currency.wrap(address(1));
        address recipient = address(2);
        uint256 feeAmount = 20;
        protocolFeesAccrued[currency] = feeAmount;

        // Act
        vm.mockCall(Currency.unwrap(currency), abi.encodeWithSelector(IERC20Minimal.transfer.selector, recipient, feeAmount), abi.encode(true));
        vm.prank(address(protocolFeeController));
        self.collectProtocolFees(recipient, currency, 0);

        // Assert
        assertEq(protocolFeesAccrued[currency], 0);
    }

    function test_collectProtocolFees_revertsIfAmountIsGreaterThanAccruedFees() external {
        // Arrange
        Currency currency = Currency.wrap(address(1));
        address recipient = address(2);
        uint256 feeAmount = 10;
        protocolFeesAccrued[currency] = feeAmount;

        // Expect
        vm.expectRevert(); // Underflow

        // Act
        vm.prank(address(protocolFeeController));
        self.collectProtocolFees(recipient, currency, feeAmount + 1);

        // Assert
        assertEq(protocolFeesAccrued[currency], feeAmount);
    }

    function test_collectProtocolFees_revertsIfCallerIsNotController() external {
        // Arrange
        Currency currency = Currency.wrap(address(1));
        address recipient = address(2);
        uint256 feeAmount = 10;
        protocolFeesAccrued[currency] = feeAmount;

        // Expect
        vm.expectRevert(InvalidCaller.selector);

        // Act
        self.collectProtocolFees(address(2), currency, 0);

        // Assert
        assertEq(protocolFeesAccrued[currency], feeAmount);
    }

    /////////////////////////////////////////////////////
    ///////////////// _fetchProtocolFee /////////////////
    /////////////////////////////////////////////////////

    function test_internal_fetchProtocolFee() external {
        // Arrange
        uint24 protocolFee = _calculateProtocolFee(1000, 1000);

        // Act
        vm.mockCall(address(protocolFeeController), abi.encodeWithSelector(IProtocolFeeController.protocolFeeForPool.selector, key), abi.encode(protocolFee));
        (bool success, uint24 fetchedProtocolFee) = _fetchProtocolFee(key);

        // Assert
        assertTrue(success);
        assertEq(fetchedProtocolFee, protocolFee);
    }

    function test_internal_fetchProtocolFee_protocolFeeControllerNotSet() external {
        // Arrange
        protocolFeeController = IProtocolFeeController(address(0));

        // Act
        (bool success, uint24 fetchedProtocolFee) = _fetchProtocolFee(key);

        // Assert
        assertFalse(success);
        assertEq(fetchedProtocolFee, 0);
    }

    function test_internal_fetchProtocolFee_invalidTypeProtocolFee() external {
        // Arrange
        uint256 protocolFee = 1e18;

        // Act
        vm.mockCall(address(protocolFeeController), abi.encodeWithSelector(IProtocolFeeController.protocolFeeForPool.selector, key), abi.encode(protocolFee));
        (bool success, uint24 fetchedProtocolFee) = _fetchProtocolFee(key);

        // Assert
        assertFalse(success);
        assertEq(fetchedProtocolFee, 0);
    }

    function test_internal_fetchProtocolFee_invalidProtocolFee() external {
        // Arrange
        uint24 protocolFee = _calculateProtocolFee(1000, 1001); // Over max fee

        // Act
        vm.mockCall(address(protocolFeeController), abi.encodeWithSelector(IProtocolFeeController.protocolFeeForPool.selector, key), abi.encode(protocolFee));
        (bool success, uint24 fetchedProtocolFee) = _fetchProtocolFee(key);

        // Assert
        assertFalse(success);
        assertEq(fetchedProtocolFee, 0);
    }

    function test_internal_fetchProtocolFee_revertsGasLeftUnderGasLimit() external {
        // Arrange
        uint reducedGas = 500000 - 1; // 1 less than the controllerGasLimit
        assembly {
            mstore(0, reducedGas)
            return(0, 32)
        }

        // Expect
        vm.expectRevert(ProtocolFeeCannotBeFetched.selector);

        // Act
        _fetchProtocolFee(key);
    }

    /////////////////////////////////////////////////////
    //////////////// _updateProtocolFees ////////////////
    /////////////////////////////////////////////////////

    function test_internal_updateProtocolFees() external {
        // Arrange
        Currency currency = Currency.wrap(address(1));
        uint256 originalAmount = 100;
        protocolFeesAccrued[currency] = originalAmount;
        uint256 amount = 50;

        // Act
        _updateProtocolFees(currency, amount);

        // Assert
        assertEq(protocolFeesAccrued[currency], originalAmount + amount);
    }

    /////////////////////////////////////////////////////
    //////////////////// test-utils /////////////////////
    /////////////////////////////////////////////////////

    function _getPool(PoolId id) internal override returns (Pool.State storage pool) {
        bytes32 slot = keccak256(abi.encodePacked("pool", id));
        assembly {
            pool.slot := slot
        }
    }

    function _calculateProtocolFee(uint16 fee0, uint16 fee1) private pure returns (uint24) {
        return (uint24(fee0) << 12) | fee1;
    }
}