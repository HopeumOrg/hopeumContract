// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20}           from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20}        from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable}          from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable}         from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard}  from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract RewardBank is Ownable(msg.sender), Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    event Deposit(address indexed token, address indexed from, uint256 amount);
    event Withdraw(address indexed token, address indexed to,   uint256 amount);

    constructor() {
        _transferOwnership(msg.sender);
    }


    /// @notice Deposit any ERC-20 into the bank
    function depositERC20Token(address token, uint256 amount)
        external
        whenNotPaused
        nonReentrant
    {
        require(amount > 0, "Zero amount");
        IERC20(token).safeTransferFrom(_msgSender(), address(this), amount);
        emit Deposit(token, _msgSender(), amount);
    }

    /// @notice Owner-only withdrawal of ERC-20
    function withdrawERC20Token(address token, uint256 amount, address to)
        external
        onlyOwner
        whenNotPaused
        nonReentrant
    {
        require(to != address(0), "Zero address");
        IERC20(token).safeTransfer(to, amount);
        emit Withdraw(token, to, amount);
    }

    /// @notice View ERC-20 balance held by the bank
    function getERC20TokenBalance(address token)
        external
        view
        returns (uint256)
    {
        return IERC20(token).balanceOf(address(this));
    }

    /* ───────────── Owner helpers ───────────── */
    function pause()  external onlyOwner { _pause();  }
    function unpause() external onlyOwner { _unpause(); }
}
