// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {CurrencyLibrary, Currency} from "../src/types/Currency.sol";
import {ProtocolFeesImplementation} from "../src/test/ProtocolFeesImplementation.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {ProtocolFeeControllerTest} from "../src/test/ProtocolFeeControllerTest.sol";
import {OutOfBoundsProtocolFeeControllerTest} from "../src/test/ProtocolFeeControllerTest.sol";
import {IProtocolFees} from "../src/interfaces/IProtocolFees.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "../src/types/Currency.sol";
import {Deployers} from "../test/utils/Deployers.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";

import "forge-std/console2.sol";

contract ProtocolFeesTest is Test, GasSnapshot, Deployers {
    using CurrencyLibrary for Currency;

    event ProtocolFeeControllerUpdated(address feeController);

    uint24 constant MAX_PROTOCOL_FEE_BOTH_TOKENS = (1000 << 12) | 1000; // 1000 1000

    ProtocolFeesImplementation protocolFees;

    function setUp() public {
        protocolFees = new ProtocolFeesImplementation(5000);
        feeController = new ProtocolFeeControllerTest();
        (currency0, currency1) = deployAndMint2Currencies();
        MockERC20(Currency.unwrap(currency0)).transfer(address(protocolFees),  2 ** 255);
    }

    function test_pfsetProtocolFeeController_succeeds() public {
        assertEq(address(protocolFees.protocolFeeController()), address(0));
        vm.expectEmit(false, false, false, true, address(protocolFees));
        emit ProtocolFeeControllerUpdated(address(feeController));
        protocolFees.setProtocolFeeController(feeController);
        assertEq(address(protocolFees.protocolFeeController()), address(feeController));
    }

    function test_setProtocolFeeController_revertsWithNotAuthorized() public {
        assertEq(address(protocolFees.protocolFeeController()), address(0));

        vm.prank(address(1)); // not the owner address
        vm.expectRevert("UNAUTHORIZED");
        protocolFees.setProtocolFeeController(feeController);
        assertEq(address(protocolFees.protocolFeeController()), address(0));
    }

    function test_setProtocolFee_revertsWithInvalidCaller() public {
        protocolFees.setProtocolFeeController(feeController);
        vm.expectRevert(IProtocolFees.InvalidCaller.selector);
        protocolFees.setProtocolFee(key, 1);
    }

    function test_setProtocolFee_revertsWithInvalidFee() public {
        protocolFees.setProtocolFeeController(feeController);
        vm.prank(address(feeController));
        vm.expectRevert(IProtocolFees.InvalidProtocolFee.selector);
        protocolFees.setProtocolFee(key, MAX_PROTOCOL_FEE_BOTH_TOKENS + 1);
    }

    function test_collectProtocolFees_revertsWithInvalidCaller() public {
        vm.expectRevert(IProtocolFees.InvalidCaller.selector);
        protocolFees.collectProtocolFees(address(1), CurrencyLibrary.NATIVE, 0);
    }

    function test_collectProtocolFees_succeeds() public {
        protocolFees.updateProtocolFees(currency0, 100);
        assertEq(protocolFees.protocolFeesAccrued(currency0), 100);
        protocolFees.setProtocolFeeController(feeController);
        vm.prank(address(feeController));
        protocolFees.collectProtocolFees(address(this), currency0, 100);
        assertEq(protocolFees.protocolFeesAccrued(currency0), 0);
        assertEq(currency0.balanceOf(address(this)), 100);
    }

    function test_fuzz_collectProtocolFees(address recipient, uint256 amount, uint256 feesAccrued) public {
        vm.assume(feesAccrued <= currency0.balanceOf(address(protocolFees)));
        vm.assume(amount <= feesAccrued);
        vm.assume(recipient != address(protocolFees));
        vm.assume(recipient != address(0));

        uint256 recipientBalanceBefore = currency0.balanceOf(recipient);
        uint256 senderBalanceBefore = currency0.balanceOf(address(protocolFees));

        protocolFees.updateProtocolFees(currency0, feesAccrued);
        assertEq(protocolFees.protocolFeesAccrued(currency0), feesAccrued);
        if (amount == 0) {
            amount = protocolFees.protocolFeesAccrued(currency0);
        }
        protocolFees.setProtocolFeeController(feeController);
        vm.prank(address(feeController));
        uint256 amountCollected = protocolFees.collectProtocolFees(recipient, currency0, amount);

        assertEq(protocolFees.protocolFeesAccrued(currency0), feesAccrued - amount);
        assertEq(currency0.balanceOf(recipient), recipientBalanceBefore + amount);
        assertEq(currency0.balanceOf(address(protocolFees)), senderBalanceBefore - amount);
        assertEq(amountCollected, amount);
    }

    function test_updateProtocolFees_succeeds() public {
        protocolFees.updateProtocolFees(currency0, 100);
        assertEq(protocolFees.protocolFeesAccrued(currency0), 100);
        protocolFees.updateProtocolFees(currency0, 200);
        assertEq(protocolFees.protocolFeesAccrued(currency0), 300);
    }

    function test_fuzz_updateProtocolFees(uint256 amount, uint256 startingAmount) public {
        protocolFees.updateProtocolFees(currency0, startingAmount);
        assertEq(protocolFees.protocolFeesAccrued(currency0), startingAmount);

        uint256 newAmount;
        unchecked {
            newAmount = startingAmount + amount;
        }

        protocolFees.updateProtocolFees(currency0, amount);
        assertEq(protocolFees.protocolFeesAccrued(currency0), newAmount);
    }

    function test_fetchProtocolFee_succeeds() public {
        protocolFees.setProtocolFeeController(feeController);
        vm.prank(address(feeController));
        (bool success, uint24 protocolFee) = protocolFees.fetchProtocolFee(key);
        assertTrue(success);
        assertEq(protocolFee, 0);
    }

    function test_fetchProtocolFee_outOfBounds() public {
        outOfBoundsFeeController = new OutOfBoundsProtocolFeeControllerTest();
        protocolFees.setProtocolFeeController(outOfBoundsFeeController);
        vm.prank(address(outOfBoundsFeeController));
        vm.expectRevert(IProtocolFees.InvalidProtocolFee.selector);
        (bool success, uint24 protocolFee) = protocolFees.fetchProtocolFee(key);
        assertFalse(success);
    }
}