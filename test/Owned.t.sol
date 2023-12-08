// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Owned} from "../src/Owned.sol";

contract OwnedTest is Test {
    Owned owned;

    function testConstructor(address owner) public {
        deployOwnedWithOwner(owner);

        assertEq(owner, owned.owner());
    }

    function testSetOwnerFromOwner(address oldOwner, address nextOwner) public {
        // set the old owner as the owner
        deployOwnedWithOwner(oldOwner);

        // old owner passes over ownership
        vm.prank(oldOwner);
        owned.setOwner(nextOwner);
        assertEq(nextOwner, owned.owner());
    }

    function testSetOwnerFromNonOwner(address oldOwner, address nextOwner) public {
        // set the old owner as the owner
        deployOwnedWithOwner(oldOwner);

        if (oldOwner != nextOwner) {
            vm.startPrank(nextOwner);
            vm.expectRevert(Owned.InvalidCaller.selector);
            owned.setOwner(nextOwner);
            vm.stopPrank();
        }
    }

    function deployOwnedWithOwner(address owner) internal {
        vm.prank(owner);
        owned = new Owned();
    }
}
