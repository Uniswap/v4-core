// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC6909Claims} from "./interfaces/external/IERC6909Claims.sol";

/// @title ERC6909
/// @notice Minimalist, gas efficient, and robust implementation of the ERC6909 Claims Token Standard.
/// @dev Based on Solmate's implementation, modified to include necessary checks for safety.
abstract contract ERC6909 is IERC6909Claims {
    /*//////////////////////////////////////////////////////////////
                                ERC6909 STORAGE
    //////////////////////////////////////////////////////////////*/

    // Stores approved operators for an owner.
    mapping(address owner => mapping(address operator => bool isOperator)) public isOperator;

    // Stores the balance of a specific claim ID for an owner.
    mapping(address owner => mapping(uint256 id => uint256 balance)) public balanceOf;

    // Stores the allowance granted by an owner to a spender for a specific claim ID.
    mapping(address owner => mapping(address spender => mapping(uint256 id => uint256 amount))) public allowance;

    /*//////////////////////////////////////////////////////////////
                                ERC6909 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC6909
    function transfer(address receiver, uint256 id, uint256 amount) public virtual returns (bool) {
        // Safety checks for balance and receiver address.
        require(receiver != address(0), "ERC6909: Transfer to zero address");
        
        // Explicit balance check to provide a descriptive error message and ensure safety.
        require(balanceOf[msg.sender][id] >= amount, "ERC6909: Insufficient balance");

        unchecked {
            balanceOf[msg.sender][id] -= amount;
        }
        balanceOf[receiver][id] += amount;

        // Note: The Transfer event's second parameter is the 'operator' (msg.sender).
        emit Transfer(msg.sender, msg.sender, receiver, id, amount);

        return true;
    }

    /// @inheritdoc IERC6909
    function transferFrom(address sender, address receiver, uint256 id, uint256 amount) public virtual returns (bool) {
        require(sender != address(0), "ERC6909: Transfer from zero address");
        require(receiver != address(0), "ERC6909: Transfer to zero address");
        require(balanceOf[sender][id] >= amount, "ERC6909: Insufficient balance");

        // Check if caller is NOT the sender AND NOT an approved operator.
        if (msg.sender != sender && !isOperator[sender][msg.sender]) {
            uint256 allowed = allowance[sender][msg.sender][id];
            
            // Critical: Check if the allowed amount is sufficient before deducting.
            require(allowed >= amount, "ERC6909: Insufficient allowance");
            
            // Only deduct allowance if it's not the max (infinite approval).
            if (allowed != type(uint256).max) {
                unchecked {
                    allowance[sender][msg.sender][id] = allowed - amount;
                }
            }
        }

        unchecked {
            balanceOf[sender][id] -= amount;
        }
        balanceOf[receiver][id] += amount;

        // Note: The Transfer event's second parameter is the 'owner' (sender).
        emit Transfer(msg.sender, sender, receiver, id, amount);

        return true;
    }

    /// @inheritdoc IERC6909
    function approve(address spender, uint256 id, uint256 amount) public virtual returns (bool) {
        allowance[msg.sender][spender][id] = amount;

        emit Approval(msg.sender, spender, id, amount);

        return true;
    }

    /// @inheritdoc IERC6909
    function setOperator(address operator, bool approved) public virtual returns (bool) {
        isOperator[msg.sender][operator] = approved;

        emit OperatorSet(msg.sender, operator, approved);

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                                ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IERC6909Claims).interfaceId // 0x0f632fb3
            || super.supportsInterface(interfaceId); // Allows for extending contracts to support ERC165
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Mints tokens and increases the receiver's balance.
    /// @param receiver The address that will receive the new tokens.
    /// @param id The ID of the claim token to mint.
    /// @param amount The amount of tokens to mint.
    function _mint(address receiver, uint256 id, uint256 amount) internal virtual {
        require(receiver != address(0), "ERC6909: Mint to zero address");
        
        balanceOf[receiver][id] += amount;

        // Transfer event for minting: from address(0) to receiver. Operator is msg.sender.
        emit Transfer(msg.sender, address(0), receiver, id, amount);
    }

    /// @notice Burns tokens and decreases the sender's balance.
    /// @param sender The address from which tokens will be burned.
    /// @param id The ID of the claim token to burn.
    /// @param amount The amount of tokens to burn.
    function _burn(address sender, uint256 id, uint256 amount) internal virtual {
        require(sender != address(0), "ERC6909: Burn from zero address");
        require(balanceOf[sender][id] >= amount, "ERC6909: Insufficient balance for burn");

        unchecked {
            balanceOf[sender][id] -= amount;
        }

        // Transfer event for burning: from sender to address(0). Operator is msg.sender.
        emit Transfer(msg.sender, sender, address(0), id, amount);
    }
}
