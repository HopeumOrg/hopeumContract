// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {RewardBank} from "../src/RewardBank.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract RewardBankTest is Test {
    RewardBank public rewardBank;
    MockERC20 public mockToken;
    address public owner;
    address public user;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        owner = address(this);
        user = address(0x1);
        rewardBank = new RewardBank();
        mockToken = new MockERC20("Mock Token", "MTK", 18);

        // Mint some tokens to owner for testing
        mockToken.mint(owner, 1000e18);
    }

    function test_Constructor() public view {
        assertEq(rewardBank.owner(), owner);
    }

    function test_DepositERC20Token() public {
        uint256 depositAmount = 100e18;
        mockToken.approve(address(rewardBank), depositAmount);

        rewardBank.depositERC20Token(address(mockToken), depositAmount);
        assertEq(mockToken.balanceOf(address(rewardBank)), depositAmount);
    }

    function testFail_DepositERC20Token_NotOwner() public {
        uint256 depositAmount = 100e18;
        vm.prank(user);
        rewardBank.depositERC20Token(address(mockToken), depositAmount);
    }

    function test_WithdrawERC20Token() public {
        uint256 depositAmount = 100e18;
        uint256 withdrawAmount = 50e18;

        // First deposit some tokens
        mockToken.approve(address(rewardBank), depositAmount);
        rewardBank.depositERC20Token(address(mockToken), depositAmount);

        // Then withdraw
        rewardBank.withdrawERC20Token(address(mockToken), withdrawAmount, user);
        assertEq(mockToken.balanceOf(user), withdrawAmount);
        assertEq(
            mockToken.balanceOf(address(rewardBank)),
            depositAmount - withdrawAmount
        );
    }

    function testFail_WithdrawERC20Token_NotOwner() public {
        uint256 withdrawAmount = 50e18;
        vm.prank(user);
        rewardBank.withdrawERC20Token(address(mockToken), withdrawAmount, user);
    }

    function testFail_WithdrawERC20Token_WhenPaused() public {
        uint256 depositAmount = 100e18;
        uint256 withdrawAmount = 50e18;

        // First deposit some tokens
        mockToken.approve(address(rewardBank), depositAmount);
        rewardBank.depositERC20Token(address(mockToken), depositAmount);

        // Pause the contract
        rewardBank.pause();

        // Try to withdraw
        rewardBank.withdrawERC20Token(address(mockToken), withdrawAmount, user);
    }

    function test_GetERC20TokenBalance() public {
        uint256 depositAmount = 100e18;

        mockToken.approve(address(rewardBank), depositAmount);
        rewardBank.depositERC20Token(address(mockToken), depositAmount);

        assertEq(
            rewardBank.getERC20TokenBalance(address(mockToken)),
            depositAmount
        );
    }

    function test_Pause() public {
        rewardBank.pause();

        uint256 withdrawAmount = 50e18;
        vm.expectRevert("Paused");
        rewardBank.withdrawERC20Token(address(mockToken), withdrawAmount, user);
    }

    function testFail_Pause_NotOwner() public {
        vm.prank(user);
        rewardBank.pause();
    }
}
