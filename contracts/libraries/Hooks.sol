// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;
import {IHooks} from '../interfaces/callback/IHooks.sol';

library Hooks {
    uint256 public constant BEFORE_SWAP_FLAG = 1 << 159;
    uint256 public constant AFTER_SWAP_FLAG = 1 << 158;
    uint256 public constant BEFORE_MODIFY_POSITION_FLAG = 1 << 157;
    uint256 public constant AFTER_MODIFY_POSITION_FLAG = 1 << 156;
    uint256 public constant BEFORE_TICK_CROSSING_FLAG = 1 << 155;
    uint256 public constant AFTER_TICK_CROSSING_FLAG = 1 << 154;

    function validateHookAddress(IHooks self, IHooks.Params calldata params) internal pure returns (bool) {
        uint256 mask = 0;
        if (params.beforeSwap) {
            mask = mask | BEFORE_SWAP_FLAG;
        }
        if (params.afterSwap) {
            mask = mask | AFTER_SWAP_FLAG;
        }
        if (params.beforeModifyPosition) {
            mask = mask | BEFORE_MODIFY_POSITION_FLAG;
        }
        if (params.afterModifyPosition) {
            mask = mask | AFTER_MODIFY_POSITION_FLAG;
        }
        if (params.beforeTickCrossing) {
            mask = mask | BEFORE_TICK_CROSSING_FLAG;
        }
        if (params.afterTickCrossing) {
            mask = mask | AFTER_TICK_CROSSING_FLAG;
        }

        return uint256(uint160(address(self))) & mask == mask;
    }

    function shouldBeforeSwap(IHooks self) internal pure returns (bool) {
        return uint256(uint160(address(self))) & BEFORE_SWAP_FLAG != 0;
    }

    function shouldAfterSwap(IHooks self) internal pure returns (bool) {
        return uint256(uint160(address(self))) & AFTER_SWAP_FLAG != 0;
    }

    function shouldBeforeModifyPosition(IHooks self) internal pure returns (bool) {
        return uint256(uint160(address(self))) & BEFORE_MODIFY_POSITION_FLAG != 0;
    }

    function shouldAfterModifyPosition(IHooks self) internal pure returns (bool) {
        return uint256(uint160(address(self))) & AFTER_MODIFY_POSITION_FLAG != 0;
    }

    function shouldBeforeTickCrossing(IHooks self) internal pure returns (bool) {
        return uint256(uint160(address(self))) & BEFORE_TICK_CROSSING_FLAG != 0;
    }

    function shouldAfterTickCrossing(IHooks self) internal pure returns (bool) {
        return uint256(uint160(address(self))) & AFTER_TICK_CROSSING_FLAG != 0;
    }
}
