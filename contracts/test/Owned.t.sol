pragma solidity ^0.8.13;

import {DSTest} from '../../foundry/testdata/lib/ds-test/src/test.sol';
import {Cheats} from '../../foundry/testdata/cheats/Cheats.sol';
import {Owned} from '../Owned.sol';

contract OwnedTest is DSTest {
    Cheats vm = Cheats(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    Owned owned;

    function testConstructor(address x) public {
        // Set x as the next call's msg.sender
        vm.prank(x);
        owned = new Owned();
        assertEq(x, owned.owner());
    }

    function testSetOwner(
        address oldOwner,
        address nextOwner,
        bool oldOwnerCalls
    ) public {
        // set the old owner as the owner
        vm.startPrank(oldOwner);
        owned = new Owned();

        if (oldOwnerCalls || nextOwner == oldOwner) {
            // old owner passes over ownership
            owned.setOwner(nextOwner);
            assertEq(nextOwner, owned.owner());
        } else {
            // someone tried to take ownership and it reverts
            vm.stopPrank();
            vm.startPrank(nextOwner);
            vm.expectRevert();
            owned.setOwner(nextOwner);
        }
    }
}
