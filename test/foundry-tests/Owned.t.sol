pragma solidity ^0.8.13;

import {DSTest} from '../../foundry/testdata/lib/ds-test/src/test.sol';
import {Cheats} from '../../foundry/testdata/cheats/Cheats.sol';
import {Owned} from '../../contracts/Owned.sol';

contract OwnedTest is DSTest {
    Cheats vm = Cheats(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
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
