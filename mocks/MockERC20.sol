// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../dependencies/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockERC20
 * @dev A simple ERC20 token implementation for testing purposes
 */
contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_
    ) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /**
     * @dev Mint tokens to a specified address
     * @param to The address that will receive the minted tokens
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /**
     * @dev Burns tokens from the caller's account
     * @param amount The amount of tokens to burn
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /**
     * @dev Burns tokens from a specified account with allowance
     * @param account The account from which tokens will be burned
     * @param amount The amount of tokens to burn
     */
    function burnFrom(address account, uint256 amount) external {
        uint256 currentAllowance = allowance(account, msg.sender);
        if (currentAllowance != type(uint256).max) {
            require(
                currentAllowance >= amount,
                "ERC20: burn amount exceeds allowance"
            );
            _approve(account, msg.sender, currentAllowance - amount);
        }
        _burn(account, amount);
    }
}
