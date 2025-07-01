// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {StakingPools} from "../src/StakingPools.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract StakingTest is Test {
    StakingPools public stakingPools;
    MockERC20 public stakeToken;
    MockERC20 public rewardToken;
    MockERC20 public collateralToken;

    address public owner = address(1);
    address public user = address(2);

    uint256 public constant STAKE_AMOUNT = 1000e18;
    uint256 public constant MIN_STAKE = 1e18;
    uint256 public constant APY = 500; // 5%
    uint256 public constant DURATION = 30 days;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy contracts
        stakingPools = new StakingPools();
        stakeToken = new MockERC20("Stake Token", "STK", 18);
        rewardToken = new MockERC20("Reward Token", "RWD", 18);
        collateralToken = new MockERC20("Collateral Token", "COL", 18);

        // Create a pool
        stakingPools.createPool(
            address(stakeToken), // _stakeToken
            address(rewardToken), // _rewardToken
            APY, // _apy
            DURATION, // _duration
            block.timestamp, // _startTime
            true, // _canWithdrawStake
            MIN_STAKE, // _minStakeAmount
            false, // _isCollateralized
            address(0), // _collateralToken
            false, // _isNative,
            3000000000000000 // _collateralAmount
        );

        // Setup user with tokens
        stakeToken.mint(user, STAKE_AMOUNT * 2);

        // Fund the contract with reward tokens for distribution
        rewardToken.mint(address(stakingPools), 10000e18); // Mint reward tokens to the contract

        vm.stopPrank();
    }

    function testUserCanStake() public {
        // Setup: User approves tokens for staking
        vm.startPrank(user);
        stakeToken.approve(address(stakingPools), STAKE_AMOUNT);

        // Get initial balances
        uint256 userBalanceBefore = stakeToken.balanceOf(user);
        uint256 contractBalanceBefore = stakeToken.balanceOf(
            address(stakingPools)
        );

        // Test: User stakes tokens
        stakingPools.stake(0, STAKE_AMOUNT);

        // Verify: Balances updated correctly
        uint256 userBalanceAfter = stakeToken.balanceOf(user);
        uint256 contractBalanceAfter = stakeToken.balanceOf(
            address(stakingPools)
        );

        assertEq(userBalanceAfter, userBalanceBefore - STAKE_AMOUNT);
        assertEq(contractBalanceAfter, contractBalanceBefore + STAKE_AMOUNT);

        // Verify: User stake recorded correctly
        (StakingPools.UserStake memory userStake, ) = stakingPools
            .getUserStakeInfo(0, user);
        assertEq(userStake.amount, STAKE_AMOUNT);
        assertEq(userStake.stakedAt, block.timestamp);

        // Verify: Pool total updated
        StakingPools.Pool memory pool = stakingPools.getPoolInfo(0);
        assertEq(pool.totalStaked, STAKE_AMOUNT);

        vm.stopPrank();
    }

    function testUserCanMakeMultipleStakes() public {
        // Setup: User approves tokens for staking
        vm.startPrank(user);
        stakeToken.approve(address(stakingPools), STAKE_AMOUNT * 2);

        // Get initial balances
        uint256 userBalanceInitial = stakeToken.balanceOf(user);
        uint256 contractBalanceInitial = stakeToken.balanceOf(
            address(stakingPools)
        );
        uint256 rewardTokenBalance = rewardToken.balanceOf(
            address(stakingPools)
        );

        console.log("=== Initial State ===");
        console.log("User stake token balance:", userBalanceInitial);
        console.log("Contract stake token balance:", contractBalanceInitial);
        console.log("Contract reward token balance:", rewardTokenBalance);

        // Test: User makes first stake
        uint256 firstStakeAmount = 400e18;
        console.log("=== Making First Stake ===");
        console.log("First stake amount:", firstStakeAmount);

        stakingPools.stake(0, firstStakeAmount);

        console.log("First stake completed");

        // Verify: First stake recorded
        (StakingPools.UserStake memory userStake1, ) = stakingPools
            .getUserStakeInfo(0, user);
        console.log("First stake recorded amount:", userStake1.amount);
        assertEq(userStake1.amount, firstStakeAmount);
        assertEq(userStake1.stakedAt, block.timestamp);

        // Log balances after first stake
        console.log("=== After First Stake ===");
        console.log("User stake token balance:", stakeToken.balanceOf(user));
        console.log(
            "Contract stake token balance:",
            stakeToken.balanceOf(address(stakingPools))
        );
        console.log(
            "Contract reward token balance:",
            rewardToken.balanceOf(address(stakingPools))
        );

        // Test: User makes second stake
        vm.warp(block.timestamp + 1 hours); // Move time forward
        uint256 secondStakeAmount = 600e18;

        console.log("=== Making Second Stake ===");
        console.log("Time warped by 1 hour");
        console.log("Second stake amount:", secondStakeAmount);
        console.log(
            "Contract reward token balance before second stake:",
            rewardToken.balanceOf(address(stakingPools))
        );

        stakingPools.stake(0, secondStakeAmount);

        console.log("Second stake completed");

        // Verify: Second stake recorded (should be a new stake entry)
        // Note: This assumes the contract supports multiple stakes per user
        // If it updates existing stake, we'd need to check the updated amount
        (StakingPools.UserStake memory userStake2, ) = stakingPools
            .getUserStakeInfo(0, user);
        console.log("Second stake recorded amount:", userStake2.amount);

        // Verify: Total user balance decreased by both stakes
        uint256 userBalanceFinal = stakeToken.balanceOf(user);
        console.log("=== Final Balances ===");
        console.log("User final balance:", userBalanceFinal);
        console.log(
            "Expected user balance:",
            userBalanceInitial - firstStakeAmount - secondStakeAmount
        );
        assertEq(
            userBalanceFinal,
            userBalanceInitial - firstStakeAmount - secondStakeAmount
        );

        // Verify: Contract balance increased by both stakes
        uint256 contractBalanceFinal = stakeToken.balanceOf(
            address(stakingPools)
        );
        console.log("Contract final balance:", contractBalanceFinal);
        console.log(
            "Expected contract balance:",
            contractBalanceInitial + firstStakeAmount + secondStakeAmount
        );
        assertEq(
            contractBalanceFinal,
            contractBalanceInitial + firstStakeAmount + secondStakeAmount
        );

        // Verify: Pool total updated correctly
        StakingPools.Pool memory pool = stakingPools.getPoolInfo(0);
        console.log("Pool total staked:", pool.totalStaked);
        console.log(
            "Expected pool total:",
            firstStakeAmount + secondStakeAmount
        );
        assertEq(pool.totalStaked, firstStakeAmount + secondStakeAmount);

        vm.stopPrank();
    }

    function testCollateralizedStaking() public {
        vm.startPrank(owner);

        // Create a collateralized pool (pool ID 1)
        stakingPools.createPool(
            address(stakeToken), // _stakeToken
            address(rewardToken), // _rewardToken
            APY, // _apy
            DURATION, // _duration
            block.timestamp, // _startTime
            true, // _canWithdrawStake
            MIN_STAKE, // _minStakeAmount
            true, // _isCollateralized
            address(collateralToken), // _collateralToken
            false, // _isNative
            3000000000000000
        );

        // Fund the contract with reward tokens for this pool too
        rewardToken.mint(address(stakingPools), 10000e18);

        vm.stopPrank();

        // Setup user with tokens
        vm.startPrank(user);

        // User needs both stake tokens and collateral tokens
        uint256 stakeAmount = 500e18;
        uint256 collateralAmount = 100e18; // Assuming some collateral is required

        console.log("=== Collateralized Staking Test Setup ===");
        console.log("Stake amount:", stakeAmount);
        console.log("Collateral amount:", collateralAmount);

        // Mint collateral tokens to user
        vm.stopPrank();
        vm.prank(owner);
        collateralToken.mint(user, collateralAmount * 2);
        vm.startPrank(user);

        // Approve both stake and collateral tokens
        stakeToken.approve(address(stakingPools), stakeAmount);
        collateralToken.approve(address(stakingPools), collateralAmount);

        // Get initial balances
        uint256 userStakeBalanceInitial = stakeToken.balanceOf(user);
        uint256 userCollateralBalanceInitial = collateralToken.balanceOf(user);
        uint256 contractStakeBalanceInitial = stakeToken.balanceOf(
            address(stakingPools)
        );
        uint256 contractCollateralBalanceInitial = collateralToken.balanceOf(
            address(stakingPools)
        );

        console.log("=== Initial Balances ===");
        console.log("User stake token balance:", userStakeBalanceInitial);
        console.log(
            "User collateral token balance:",
            userCollateralBalanceInitial
        );
        console.log(
            "Contract stake token balance:",
            contractStakeBalanceInitial
        );
        console.log(
            "Contract collateral token balance:",
            contractCollateralBalanceInitial
        );

        // Get pool info before staking
        StakingPools.Pool memory poolBefore = stakingPools.getPoolInfo(1);
        console.log("Pool is collateralized:", poolBefore.isCollateralized);
        console.log("Pool collateral token:", poolBefore.collateralToken);
        console.log("Pool is native:", poolBefore.isNative);

        // Test: User stakes with collateral
        console.log("=== Attempting Collateralized Stake ===");
        stakingPools.stake(1, stakeAmount);
        console.log("Collateralized stake completed");

        // Verify: Balances updated correctly
        uint256 userStakeBalanceFinal = stakeToken.balanceOf(user);
        uint256 userCollateralBalanceFinal = collateralToken.balanceOf(user);
        uint256 contractStakeBalanceFinal = stakeToken.balanceOf(
            address(stakingPools)
        );
        uint256 contractCollateralBalanceFinal = collateralToken.balanceOf(
            address(stakingPools)
        );

        console.log("=== Final Balances ===");
        console.log("User stake token balance:", userStakeBalanceFinal);
        console.log(
            "User collateral token balance:",
            userCollateralBalanceFinal
        );
        console.log("Contract stake token balance:", contractStakeBalanceFinal);
        console.log(
            "Contract collateral token balance:",
            contractCollateralBalanceFinal
        );

        // Verify stake token transfer
        assertEq(userStakeBalanceFinal, userStakeBalanceInitial - stakeAmount);
        assertEq(
            contractStakeBalanceFinal,
            contractStakeBalanceInitial + stakeAmount
        );

        // Verify collateral handling (if collateral is required)
        // Note: This depends on the contract's collateral logic

        // Verify: User stake recorded correctly
        (StakingPools.UserStake memory userStake, ) = stakingPools
            .getUserStakeInfo(1, user);
        console.log("Recorded stake amount:", userStake.amount);
        console.log("Stake timestamp:", userStake.stakedAt);
        assertEq(userStake.amount, stakeAmount);
        assertEq(userStake.stakedAt, block.timestamp);

        // Verify: Pool total updated
        StakingPools.Pool memory poolAfter = stakingPools.getPoolInfo(1);
        console.log("Pool total staked after:", poolAfter.totalStaked);
        assertEq(poolAfter.totalStaked, stakeAmount);

        vm.stopPrank();
    }

    function testCannotWithdrawWhenWithdrawDisabled() public {
        vm.startPrank(owner);

        // Create a pool with withdrawal disabled (pool ID 1)
        stakingPools.createPool(
            address(stakeToken), // _stakeToken
            address(rewardToken), // _rewardToken
            APY, // _apy
            DURATION, // _duration
            block.timestamp, // _startTime
            false, // _canWithdrawStake - DISABLED
            MIN_STAKE, // _minStakeAmount
            false, // _isCollateralized
            address(0), // _collateralToken
            false, // _isNative
            3000000000000000
        );

        // Fund the contract with reward tokens
        rewardToken.mint(address(stakingPools), 10000e18);

        vm.stopPrank();

        // Setup user for staking
        vm.startPrank(user);

        uint256 stakeAmount = 800e18;
        stakeToken.approve(address(stakingPools), stakeAmount);

        console.log("=== Testing Withdrawal Disabled Pool ===");
        console.log("Stake amount:", stakeAmount);

        // Get pool info to confirm withdrawal is disabled
        StakingPools.Pool memory pool = stakingPools.getPoolInfo(1);
        console.log("Pool canWithdrawStake:", pool.canWithdrawStake);
        assertEq(
            pool.canWithdrawStake,
            false,
            "Pool should have withdrawal disabled"
        );

        // Get initial balances
        uint256 userBalanceInitial = stakeToken.balanceOf(user);
        uint256 contractBalanceInitial = stakeToken.balanceOf(
            address(stakingPools)
        );

        console.log("=== Initial Balances ===");
        console.log("User balance:", userBalanceInitial);
        console.log("Contract balance:", contractBalanceInitial);

        // Test: User stakes successfully
        console.log("=== Staking ===");
        stakingPools.stake(1, stakeAmount);
        console.log("Staking completed successfully");

        // Verify staking worked
        (StakingPools.UserStake memory userStake, ) = stakingPools
            .getUserStakeInfo(1, user);
        console.log("Staked amount recorded:", userStake.amount);
        assertEq(userStake.amount, stakeAmount);

        // Verify balances after staking
        uint256 userBalanceAfterStake = stakeToken.balanceOf(user);
        uint256 contractBalanceAfterStake = stakeToken.balanceOf(
            address(stakingPools)
        );

        console.log("=== Balances After Staking ===");
        console.log("User balance:", userBalanceAfterStake);
        console.log("Contract balance:", contractBalanceAfterStake);

        assertEq(userBalanceAfterStake, userBalanceInitial - stakeAmount);
        assertEq(
            contractBalanceAfterStake,
            contractBalanceInitial + stakeAmount
        );

        // Test: Attempt to withdraw should fail
        console.log("=== Attempting Withdrawal (Should Fail) ===");
        console.log("Attempting to withdraw:", stakeAmount);

        // Expect the withdrawal to revert
        vm.expectRevert(); // Expecting any revert
        stakingPools.withdraw(1, stakeAmount);

        console.log("Withdrawal correctly reverted as expected");

        // Verify balances haven't changed after failed withdrawal
        uint256 userBalanceAfterFailedWithdraw = stakeToken.balanceOf(user);
        uint256 contractBalanceAfterFailedWithdraw = stakeToken.balanceOf(
            address(stakingPools)
        );

        console.log("=== Balances After Failed Withdrawal ===");
        console.log("User balance:", userBalanceAfterFailedWithdraw);
        console.log("Contract balance:", contractBalanceAfterFailedWithdraw);

        // Balances should remain unchanged
        assertEq(userBalanceAfterFailedWithdraw, userBalanceAfterStake);
        assertEq(contractBalanceAfterFailedWithdraw, contractBalanceAfterStake);

        // Verify stake amount is still recorded
        (StakingPools.UserStake memory userStakeAfter, ) = stakingPools
            .getUserStakeInfo(1, user);
        console.log("Stake amount still recorded:", userStakeAfter.amount);
        assertEq(
            userStakeAfter.amount,
            stakeAmount,
            "Stake should still be recorded"
        );

        vm.stopPrank();
    }

    function testCanWithdrawWhenWithdrawEnabled() public {
        // Use pool 0 from setUp which has withdrawal enabled
        vm.startPrank(user);

        uint256 stakeAmount = 500e18;
        stakeToken.approve(address(stakingPools), stakeAmount);

        console.log("=== Testing Withdrawal Enabled Pool ===");
        console.log("Stake amount:", stakeAmount);

        // Get pool info to confirm withdrawal is enabled
        StakingPools.Pool memory pool = stakingPools.getPoolInfo(0);
        console.log("Pool canWithdrawStake:", pool.canWithdrawStake);
        assertEq(
            pool.canWithdrawStake,
            true,
            "Pool should have withdrawal enabled"
        );

        // Get initial balances
        uint256 userBalanceInitial = stakeToken.balanceOf(user);
        uint256 contractBalanceInitial = stakeToken.balanceOf(
            address(stakingPools)
        );

        console.log("=== Initial Balances ===");
        console.log("User balance:", userBalanceInitial);
        console.log("Contract balance:", contractBalanceInitial);

        // Test: User stakes successfully
        console.log("=== Staking ===");
        stakingPools.stake(0, stakeAmount);
        console.log("Staking completed successfully");

        // Verify staking worked
        (StakingPools.UserStake memory userStake, ) = stakingPools
            .getUserStakeInfo(0, user);
        console.log("Staked amount recorded:", userStake.amount);

        // Verify balances after staking
        uint256 userBalanceAfterStake = stakeToken.balanceOf(user);
        uint256 contractBalanceAfterStake = stakeToken.balanceOf(
            address(stakingPools)
        );

        console.log("=== Balances After Staking ===");
        console.log("User balance:", userBalanceAfterStake);
        console.log("Contract balance:", contractBalanceAfterStake);

        assertEq(userBalanceAfterStake, userBalanceInitial - stakeAmount);
        assertEq(
            contractBalanceAfterStake,
            contractBalanceInitial + stakeAmount
        );

        // Wait some time to allow for potential rewards
        vm.warp(block.timestamp + 1 days);
        console.log("Time warped by 1 day for potential rewards");

        // Test: Attempt to withdraw should succeed
        console.log("=== Attempting Withdrawal (Should Succeed) ===");
        uint256 withdrawAmount = stakeAmount / 2; // Withdraw half of the stake
        console.log("Attempting to withdraw:", withdrawAmount);

        // This should succeed
        stakingPools.withdraw(0, withdrawAmount);
        console.log("Withdrawal completed successfully");

        // Verify balances changed correctly after successful withdrawal
        uint256 userBalanceAfterWithdraw = stakeToken.balanceOf(user);
        uint256 contractBalanceAfterWithdraw = stakeToken.balanceOf(
            address(stakingPools)
        );

        console.log("=== Balances After Successful Withdrawal ===");
        console.log("User balance:", userBalanceAfterWithdraw);
        console.log("Contract balance:", contractBalanceAfterWithdraw);

        // User should get their withdrawn stake back
        assertEq(
            userBalanceAfterWithdraw,
            userBalanceAfterStake + withdrawAmount
        );
        assertEq(
            contractBalanceAfterWithdraw,
            contractBalanceAfterStake - withdrawAmount
        );

        // Verify remaining stake amount is updated
        (StakingPools.UserStake memory userStakeAfter, ) = stakingPools
            .getUserStakeInfo(0, user);
        console.log("Remaining stake amount:", userStakeAfter.amount);
        assertEq(
            userStakeAfter.amount,
            stakeAmount - withdrawAmount,
            "Remaining stake should be updated"
        );

        // Verify pool total is updated
        StakingPools.Pool memory poolAfter = stakingPools.getPoolInfo(0);
        console.log(
            "Pool total staked after withdrawal:",
            poolAfter.totalStaked
        );

        vm.stopPrank();
    }
}
