// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {StakingPools} from "../src/StakingPools.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract StakingPoolsRewardsTest is Test {
    StakingPools public stakingPools;
    MockERC20 public rewardToken;

    address public owner;
    address public user;

    uint256 public constant INITIAL_MINT = 10000e18;
    uint256 public constant DEPOSIT_AMOUNT = 5000e18;

    function setUp() public {
        owner = address(this);
        user = address(0x1);

        // Deploy contracts
        stakingPools = new StakingPools();

        // Create tokens
        rewardToken = new MockERC20("Reward Token", "RWD", 18);

        // Mint tokens
        rewardToken.mint(owner, INITIAL_MINT);
    }

    function test_DepositRewardTokens() public {
        // Approve and deposit reward tokens
        rewardToken.approve(address(stakingPools), DEPOSIT_AMOUNT);
        stakingPools.depositRewardTokens(address(rewardToken), DEPOSIT_AMOUNT);

        // Check reward token balance in contract
        assertEq(
            stakingPools.getRewardTokenBalance(address(rewardToken)),
            DEPOSIT_AMOUNT
        );
        assertEq(rewardToken.balanceOf(address(stakingPools)), DEPOSIT_AMOUNT);
    }

    function testFail_DepositRewardTokens_NotOwner() public {
        // Try to deposit as non-owner
        vm.startPrank(user);
        rewardToken.approve(address(stakingPools), DEPOSIT_AMOUNT);
        stakingPools.depositRewardTokens(address(rewardToken), DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    function test_WithdrawRewardTokens() public {
        // First deposit tokens
        rewardToken.approve(address(stakingPools), DEPOSIT_AMOUNT);
        stakingPools.depositRewardTokens(address(rewardToken), DEPOSIT_AMOUNT);

        // Then withdraw half
        uint256 withdrawAmount = DEPOSIT_AMOUNT / 2;
        stakingPools.withdrawRewardTokens(address(rewardToken), withdrawAmount);

        // Check balances
        assertEq(
            stakingPools.getRewardTokenBalance(address(rewardToken)),
            DEPOSIT_AMOUNT - withdrawAmount
        );
        assertEq(
            rewardToken.balanceOf(address(stakingPools)),
            DEPOSIT_AMOUNT - withdrawAmount
        );
    }

    function testFail_WithdrawRewardTokens_NotOwner() public {
        // First deposit tokens
        rewardToken.approve(address(stakingPools), DEPOSIT_AMOUNT);
        stakingPools.depositRewardTokens(address(rewardToken), DEPOSIT_AMOUNT);

        // Try to withdraw as non-owner
        vm.startPrank(user);
        stakingPools.withdrawRewardTokens(
            address(rewardToken),
            DEPOSIT_AMOUNT / 2
        );
        vm.stopPrank();
    }

    function testFail_WithdrawRewardTokens_InsufficientBalance() public {
        // First deposit tokens
        rewardToken.approve(address(stakingPools), DEPOSIT_AMOUNT);
        stakingPools.depositRewardTokens(address(rewardToken), DEPOSIT_AMOUNT);

        // Try to withdraw more than deposited
        stakingPools.withdrawRewardTokens(
            address(rewardToken),
            DEPOSIT_AMOUNT * 2
        );
    }

    function test_GetRewardTokenBalance() public {
        // First deposit tokens
        rewardToken.approve(address(stakingPools), DEPOSIT_AMOUNT);
        stakingPools.depositRewardTokens(address(rewardToken), DEPOSIT_AMOUNT);

        // Check balance
        assertEq(
            stakingPools.getRewardTokenBalance(address(rewardToken)),
            DEPOSIT_AMOUNT
        );
    }
}
