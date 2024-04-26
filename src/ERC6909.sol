// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IERC6909Claims} from "./interfaces/external/IERC6909Claims.sol";

/// @notice Minimalist and gas efficient standard ERC6909 implementation.
/// @author Solmate (https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC6909.sol)
/// @dev Copied from the commit at 4b47a19038b798b4a33d9749d25e570443520647
/// @dev This contract has been modified from the implementation at the above link.
abstract contract ERC6909 is IERC6909Claims {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event OperatorSet(address indexed owner, address indexed operator, bool approved);

    event Approval(address indexed owner, address indexed spender, uint256 indexed id, uint256 amount);

    event Transfer(address caller, address indexed from, address indexed to, uint256 indexed id, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                             ERC6909 STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(address => mapping(address => bool)) public isOperator;

    mapping(address => mapping(uint256 => uint256)) public balanceOf;

    mapping(bytes32 => uint256) private _allowance;

    /*//////////////////////////////////////////////////////////////
                              ERC6909 GETTERS
    //////////////////////////////////////////////////////////////*/

    function allowance(address owner, address spender, uint256 id) external view returns(uint256 allowanceValue) {
        allowanceValue = _getAllowance(owner, spender, id);
    }

    /*//////////////////////////////////////////////////////////////
                              ERC6909 LOGIC
    //////////////////////////////////////////////////////////////*/

    function transfer(address receiver, uint256 id, uint256 amount) public virtual returns (bool) {
        balanceOf[msg.sender][id] -= amount;

        balanceOf[receiver][id] += amount;

        emit Transfer(msg.sender, msg.sender, receiver, id, amount);

        return true;
    }

    function transferFrom(address sender, address receiver, uint256 id, uint256 amount) public virtual returns (bool) {
        if (msg.sender != sender && !isOperator[sender][msg.sender]) {
            uint256 allowed = _getAllowance(sender, msg.sender, id);
            if (allowed != type(uint256).max) _setAllowance(sender, msg.sender, id, allowed - amount);
        }

        balanceOf[sender][id] -= amount;

        balanceOf[receiver][id] += amount;

        emit Transfer(msg.sender, sender, receiver, id, amount);

        return true;
    }

    function approve(address spender, uint256 id, uint256 amount) public virtual returns (bool) {
        _setAllowance(msg.sender, spender, id, amount);

        emit Approval(msg.sender, spender, id, amount);

        return true;
    }

    function setOperator(address operator, bool approved) public virtual returns (bool) {
        isOperator[msg.sender][operator] = approved;

        emit OperatorSet(msg.sender, operator, approved);

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                              ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == 0x01ffc9a7 // ERC165 Interface ID for ERC165
            || interfaceId == 0x0f632fb3; // ERC165 Interface ID for ERC6909
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _mint(address receiver, uint256 id, uint256 amount) internal virtual {
        balanceOf[receiver][id] += amount;

        emit Transfer(msg.sender, address(0), receiver, id, amount);
    }

    function _burn(address sender, uint256 id, uint256 amount) internal virtual {
        balanceOf[sender][id] -= amount;

        emit Transfer(msg.sender, sender, address(0), id, amount);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL STORAGE LOGIC
    //////////////////////////////////////////////////////////////*/

    function _getAllowance(address owner, address spender, uint256 id)
        internal
        view
        returns (uint256 allowanceValue)
    {
        bytes32 allowanceSlot = _getAllowanceSlot(owner, spender, id);
        /// @solidity memory-safe-assembly
        assembly {
            allowanceValue := sload(allowanceSlot)
        }
    }

    function _setAllowance(address owner, address spender, uint256 id, uint256 value) internal {
        bytes32 allowanceSlot = _getAllowanceSlot(owner, spender, id);
        /// @solidity memory-safe-assembly
        assembly {
            sstore(allowanceSlot, value)
        }
    }

    function _getAllowanceSlot(address owner, address spender, uint256 id) internal pure returns(bytes32 allowanceSlot) {
        //allowanceSlot = keccak256(abi.encode(slot, owner, spender, id));
        /// @solidity memory-safe-assembly
        assembly {
            let cache := mload(0x60)
            mstore(0x60, id)
            let pointer := mload(0x40)
            mstore(0x40, spender)
            mstore(0x20, owner)
            mstore(0, _allowance.slot)
            allowanceSlot := keccak256(0x00, 0x80)

            mstore(0x40, pointer)
            mstore(0x60, cache)
        }
    }
}
