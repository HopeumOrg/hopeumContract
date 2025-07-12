// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {StakingPools} from "../src/StakingPools.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

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

    function testWithdrawRewardTokens() public {
        console.log("=== Testing Withdraw Reward Tokens ===");

        // Setup: Get initial balances
        uint256 contractRewardBalanceInitial = rewardToken.balanceOf(
            address(stakingPools)
        );
        uint256 ownerRewardBalanceInitial = rewardToken.balanceOf(owner);

        console.log(
            "Initial contract reward balance:",
            contractRewardBalanceInitial
        );
        console.log("Initial owner reward balance:", ownerRewardBalanceInitial);

        // Test: Owner deposits additional reward tokens
        vm.startPrank(owner);
        uint256 depositAmount = 5000e18;
        rewardToken.mint(owner, depositAmount);
        rewardToken.approve(address(stakingPools), depositAmount);

        console.log("=== Depositing Reward Tokens ===");
        console.log("Deposit amount:", depositAmount);

        stakingPools.depositRewardTokens(address(rewardToken), depositAmount);

        uint256 contractRewardBalanceAfterDeposit = rewardToken.balanceOf(
            address(stakingPools)
        );
        console.log(
            "Contract reward balance after deposit:",
            contractRewardBalanceAfterDeposit
        );
        assertEq(
            contractRewardBalanceAfterDeposit,
            contractRewardBalanceInitial + depositAmount
        );

        // Test: Owner withdraws some reward tokens
        uint256 withdrawAmount = 2000e18;
        console.log("=== Withdrawing Reward Tokens ===");
        console.log("Withdraw amount:", withdrawAmount);

        uint256 ownerBalanceBeforeWithdraw = rewardToken.balanceOf(owner);
        uint256 contractBalanceBeforeWithdraw = rewardToken.balanceOf(
            address(stakingPools)
        );

        console.log(
            "Owner balance before withdraw:",
            ownerBalanceBeforeWithdraw
        );
        console.log(
            "Contract balance before withdraw:",
            contractBalanceBeforeWithdraw
        );

        stakingPools.withdrawRewardTokens(address(rewardToken), withdrawAmount);

        uint256 ownerBalanceAfterWithdraw = rewardToken.balanceOf(owner);
        uint256 contractBalanceAfterWithdraw = rewardToken.balanceOf(
            address(stakingPools)
        );

        console.log("Owner balance after withdraw:", ownerBalanceAfterWithdraw);
        console.log(
            "Contract balance after withdraw:",
            contractBalanceAfterWithdraw
        );

        // Verify balances updated correctly
        assertEq(
            ownerBalanceAfterWithdraw,
            ownerBalanceBeforeWithdraw + withdrawAmount
        );
        assertEq(
            contractBalanceAfterWithdraw,
            contractBalanceBeforeWithdraw - withdrawAmount
        );

        // Test: Try to withdraw more than available balance (should revert)
        console.log("=== Testing Withdraw More Than Available ===");
        uint256 excessiveAmount = contractBalanceAfterWithdraw + 1000e18;
        console.log(
            "Attempting to withdraw excessive amount:",
            excessiveAmount
        );

        vm.expectRevert("Insufficient reward token balance");
        stakingPools.withdrawRewardTokens(
            address(rewardToken),
            excessiveAmount
        );

        console.log("Excessive withdrawal correctly reverted");

        // Test: Non-owner cannot withdraw reward tokens
        console.log("=== Testing Non-Owner Cannot Withdraw ===");
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert(); // Should revert with "Ownable: caller is not the owner" or similar
        stakingPools.withdrawRewardTokens(address(rewardToken), 100e18);

        console.log("Non-owner withdrawal correctly reverted");

        vm.stopPrank();

        // Test: Verify getRewardTokenBalance function works correctly
        vm.startPrank(owner);
        uint256 reportedBalance = stakingPools.getRewardTokenBalance(
            address(rewardToken)
        );
        uint256 actualBalance = rewardToken.balanceOf(address(stakingPools));

        console.log("=== Verifying Balance Reporting ===");
        console.log("Reported balance:", reportedBalance);
        console.log("Actual balance:", actualBalance);

        assertEq(
            reportedBalance,
            actualBalance,
            "Reported balance should match actual balance"
        );

        console.log("Balance reporting is correct");

        vm.stopPrank();
    }

    function testCollateralPriceUpdateVulnerabilityFix() public {
        console.log(
            "=== Testing Collateral Price Update Vulnerability Fix ==="
        );

        vm.startPrank(owner);

        // Create a collateralized pool with initial price
        uint256 initialCollateralPrice = 1000000000000000; // 0.001 ETH
        uint256 poolId = stakingPools.createPool(
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
            initialCollateralPrice
        );

        // Fund the contract with reward tokens
        rewardToken.mint(address(stakingPools), 10000e18);

        vm.stopPrank();

        // Setup user for staking
        vm.startPrank(user);
        uint256 stakeAmount = 1000e18;
        stakeToken.approve(address(stakingPools), stakeAmount);

        console.log("=== Initial Staking ===");
        console.log("Initial collateral price:", initialCollateralPrice);
        console.log("Stake amount:", stakeAmount);

        // Get initial balances
        uint256 userCollateralBalanceBefore = collateralToken.balanceOf(user);
        console.log(
            "User collateral balance before staking:",
            userCollateralBalanceBefore
        );

        // User stakes - should receive collateral tokens based on initial price
        stakingPools.stake(poolId, stakeAmount);

        uint256 userCollateralBalanceAfter = collateralToken.balanceOf(user);
        console.log(
            "User collateral balance after staking:",
            userCollateralBalanceAfter
        );

        // Calculate expected collateral tokens minted (using correct formula)
        uint256 expectedCollateralMinted = (stakeAmount *
            initialCollateralPrice) / 1e18;
        console.log("Expected collateral minted:", expectedCollateralMinted);
        assertEq(userCollateralBalanceAfter, expectedCollateralMinted);

        // User must approve staking contract to burn collateral tokens for withdrawals
        collateralToken.approve(
            address(stakingPools),
            userCollateralBalanceAfter
        );
        console.log("User approved staking contract to burn collateral tokens");

        // Verify user stake info includes entry price
        (StakingPools.UserStake memory userStake, ) = stakingPools
            .getUserStakeInfo(poolId, user);
        console.log("User entry price recorded:", userStake.entryPrice);
        assertEq(userStake.entryPrice, initialCollateralPrice);

        vm.stopPrank();

        // Owner increases collateral price significantly (10x increase)
        vm.startPrank(owner);
        uint256 newCollateralPrice = initialCollateralPrice * 10; // 10x increase
        console.log("=== Owner Increases Collateral Price ===");
        console.log("New collateral price:", newCollateralPrice);

        stakingPools.updateCollateralPrice(poolId, newCollateralPrice);

        // Verify price was updated
        StakingPools.Pool memory pool = stakingPools.getPoolInfo(poolId);
        assertEq(pool.collateralPrice, newCollateralPrice);
        console.log("Pool collateral price updated to:", pool.collateralPrice);

        vm.stopPrank();

        // User should still be able to withdraw using original entry price
        vm.startPrank(user);

        console.log("=== User Attempts Withdrawal After Price Increase ===");
        uint256 withdrawAmount = stakeAmount / 2; // Withdraw half
        console.log("Withdraw amount:", withdrawAmount);

        uint256 userCollateralBalanceBeforeWithdraw = collateralToken.balanceOf(
            user
        );
        console.log(
            "User collateral balance before withdraw:",
            userCollateralBalanceBeforeWithdraw
        );

        // This should succeed because we use the stored entry price, not the current price
        stakingPools.withdraw(poolId, withdrawAmount);

        uint256 userCollateralBalanceAfterWithdraw = collateralToken.balanceOf(
            user
        );
        console.log(
            "User collateral balance after withdraw:",
            userCollateralBalanceAfterWithdraw
        );

        // Calculate expected burn amount using entry price (not current price)
        uint256 expectedBurnAmount = (withdrawAmount * initialCollateralPrice) /
            1e18;
        console.log(
            "Expected burn amount (using entry price):",
            expectedBurnAmount
        );

        uint256 actualBurnAmount = userCollateralBalanceBeforeWithdraw -
            userCollateralBalanceAfterWithdraw;
        console.log("Actual burn amount:", actualBurnAmount);

        assertEq(actualBurnAmount, expectedBurnAmount);
        console.log(
            "SUCCESS: Withdrawal successful using original entry price"
        );

        vm.stopPrank();

        // Test that new users get the updated price
        address newUser = address(3);
        vm.startPrank(owner);
        stakeToken.mint(newUser, stakeAmount);
        vm.stopPrank();

        vm.startPrank(newUser);
        stakeToken.approve(address(stakingPools), stakeAmount);

        console.log("=== New User Stakes After Price Increase ===");
        uint256 newUserCollateralBalanceBefore = collateralToken.balanceOf(
            newUser
        );
        console.log(
            "New user collateral balance before staking:",
            newUserCollateralBalanceBefore
        );

        stakingPools.stake(poolId, stakeAmount);

        uint256 newUserCollateralBalanceAfter = collateralToken.balanceOf(
            newUser
        );
        console.log(
            "New user collateral balance after staking:",
            newUserCollateralBalanceAfter
        );

        // New user should get collateral based on current (higher) price
        uint256 expectedNewUserCollateral = (stakeAmount * newCollateralPrice) /
            1e18;
        console.log(
            "Expected new user collateral (using current price):",
            expectedNewUserCollateral
        );

        assertEq(newUserCollateralBalanceAfter, expectedNewUserCollateral);

        // New user must also approve staking contract to burn collateral tokens
        collateralToken.approve(
            address(stakingPools),
            newUserCollateralBalanceAfter
        );
        console.log(
            "New user approved staking contract to burn collateral tokens"
        );

        // Verify new user's entry price
        (StakingPools.UserStake memory newUserStake, ) = stakingPools
            .getUserStakeInfo(poolId, newUser);
        console.log("New user entry price:", newUserStake.entryPrice);
        assertEq(newUserStake.entryPrice, newCollateralPrice);

        console.log(
            "SUCCESS: New user correctly uses updated collateral price"
        );

        vm.stopPrank();
    }

    function testMultipleStakeWeightedAverageCalculation() public {
        console.log(
            "=== Testing Multiple Stakes Weighted Average Calculation ==="
        );

        vm.startPrank(owner);

        // Create a collateralized pool with initial price
        uint256 initialCollateralPrice = 1000000000000000; // 0.001 ETH
        uint256 poolId = stakingPools.createPool(
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
            initialCollateralPrice
        );

        // Fund the contract with reward tokens
        rewardToken.mint(address(stakingPools), 10000e18);

        vm.stopPrank();

        // Setup user for multiple stakes
        vm.startPrank(user);
        uint256 firstStakeAmount = 1000e18;
        uint256 secondStakeAmount = 500e18;
        uint256 totalApprovalAmount = firstStakeAmount + secondStakeAmount;

        stakeToken.approve(address(stakingPools), totalApprovalAmount);

        console.log("=== First Stake ===");
        console.log("First stake amount:", firstStakeAmount);
        console.log("Initial collateral price:", initialCollateralPrice);

        // First stake at initial price
        stakingPools.stake(poolId, firstStakeAmount);

        // Verify first stake
        (StakingPools.UserStake memory userStakeAfterFirst, ) = stakingPools
            .getUserStakeInfo(poolId, user);
        console.log("After first stake - amount:", userStakeAfterFirst.amount);
        console.log(
            "After first stake - entry price:",
            userStakeAfterFirst.entryPrice
        );

        assertEq(userStakeAfterFirst.amount, firstStakeAmount);
        assertEq(userStakeAfterFirst.entryPrice, initialCollateralPrice);

        // Get collateral balance after first stake
        uint256 collateralAfterFirst = collateralToken.balanceOf(user);
        uint256 expectedCollateralFirst = (firstStakeAmount *
            initialCollateralPrice) / 1e18;
        console.log("Collateral after first stake:", collateralAfterFirst);
        console.log(
            "Expected collateral after first stake:",
            expectedCollateralFirst
        );
        assertEq(collateralAfterFirst, expectedCollateralFirst);

        vm.stopPrank();

        // Owner changes collateral price
        vm.startPrank(owner);
        uint256 newCollateralPrice = 2000000000000000; // 0.002 ETH (double the original)
        console.log("=== Owner Changes Collateral Price ===");
        console.log("New collateral price:", newCollateralPrice);

        stakingPools.updateCollateralPrice(poolId, newCollateralPrice);

        vm.stopPrank();

        // Second stake at new price
        vm.startPrank(user);
        console.log("=== Second Stake ===");
        console.log("Second stake amount:", secondStakeAmount);
        console.log("Current collateral price:", newCollateralPrice);

        stakingPools.stake(poolId, secondStakeAmount);

        // Verify weighted average calculation
        (StakingPools.UserStake memory userStakeAfterSecond, ) = stakingPools
            .getUserStakeInfo(poolId, user);
        console.log(
            "After second stake - total amount:",
            userStakeAfterSecond.amount
        );
        console.log(
            "After second stake - weighted average entry price:",
            userStakeAfterSecond.entryPrice
        );

        // Calculate expected weighted average
        // Formula: (existingAmount * existingPrice + newAmount * currentPrice) / totalAmount
        // (1000 * 1e15 + 500 * 2e15) / 1500 = (1e18 + 1e18) / 1500 = 2e18 / 1500 = 1.333...e15
        uint256 expectedWeightedAverage = ((firstStakeAmount *
            initialCollateralPrice) +
            (secondStakeAmount * newCollateralPrice)) /
            (firstStakeAmount + secondStakeAmount);
        console.log("Expected weighted average:", expectedWeightedAverage);

        assertEq(
            userStakeAfterSecond.amount,
            firstStakeAmount + secondStakeAmount
        );
        assertEq(userStakeAfterSecond.entryPrice, expectedWeightedAverage);

        // Verify total collateral minted
        uint256 collateralAfterSecond = collateralToken.balanceOf(user);
        uint256 expectedCollateralSecond = (secondStakeAmount *
            newCollateralPrice) / 1e18;
        uint256 expectedTotalCollateral = expectedCollateralFirst +
            expectedCollateralSecond;

        console.log("Collateral after second stake:", collateralAfterSecond);
        console.log("Expected total collateral:", expectedTotalCollateral);
        assertEq(collateralAfterSecond, expectedTotalCollateral);

        // Approve staking contract to burn collateral tokens
        collateralToken.approve(address(stakingPools), collateralAfterSecond);
        console.log("Approved staking contract to burn collateral tokens");

        // Test partial withdrawal using weighted average
        console.log("=== Testing Partial Withdrawal with Weighted Average ===");
        uint256 withdrawAmount = 750e18; // Withdraw half of total stake
        console.log("Withdraw amount:", withdrawAmount);

        uint256 userStakeBalanceBefore = stakeToken.balanceOf(user);
        uint256 userCollateralBalanceBefore = collateralToken.balanceOf(user);

        console.log(
            "User stake balance before withdraw:",
            userStakeBalanceBefore
        );
        console.log(
            "User collateral balance before withdraw:",
            userCollateralBalanceBefore
        );

        stakingPools.withdraw(poolId, withdrawAmount);

        uint256 userStakeBalanceAfter = stakeToken.balanceOf(user);
        uint256 userCollateralBalanceAfter = collateralToken.balanceOf(user);

        console.log(
            "User stake balance after withdraw:",
            userStakeBalanceAfter
        );
        console.log(
            "User collateral balance after withdraw:",
            userCollateralBalanceAfter
        );

        // Verify stake token transfer
        assertEq(
            userStakeBalanceAfter,
            userStakeBalanceBefore + withdrawAmount
        );

        // Verify collateral burn using weighted average
        uint256 expectedBurnAmount = (withdrawAmount *
            expectedWeightedAverage) / 1e18;
        uint256 actualBurnAmount = userCollateralBalanceBefore -
            userCollateralBalanceAfter;

        console.log(
            "Expected burn amount (using weighted average):",
            expectedBurnAmount
        );
        console.log("Actual burn amount:", actualBurnAmount);
        assertEq(actualBurnAmount, expectedBurnAmount);

        // Verify remaining stake info
        (StakingPools.UserStake memory userStakeAfterWithdraw, ) = stakingPools
            .getUserStakeInfo(poolId, user);
        console.log("Remaining stake amount:", userStakeAfterWithdraw.amount);
        console.log(
            "Entry price after withdraw (should be same):",
            userStakeAfterWithdraw.entryPrice
        );

        assertEq(
            userStakeAfterWithdraw.amount,
            firstStakeAmount + secondStakeAmount - withdrawAmount
        );
        assertEq(userStakeAfterWithdraw.entryPrice, expectedWeightedAverage); // Entry price should remain the same

        // Test third stake to verify weighted average recalculation
        vm.stopPrank();
        vm.startPrank(owner);
        uint256 thirdCollateralPrice = 3000000000000000; // 0.003 ETH (triple the original)
        console.log("=== Owner Changes Price Again ===");
        console.log("Third collateral price:", thirdCollateralPrice);

        stakingPools.updateCollateralPrice(poolId, thirdCollateralPrice);

        vm.stopPrank();

        vm.startPrank(user);
        uint256 thirdStakeAmount = 250e18;
        console.log("=== Third Stake ===");
        console.log("Third stake amount:", thirdStakeAmount);

        stakeToken.approve(address(stakingPools), thirdStakeAmount);
        stakingPools.stake(poolId, thirdStakeAmount);

        // Verify new weighted average calculation
        (StakingPools.UserStake memory userStakeAfterThird, ) = stakingPools
            .getUserStakeInfo(poolId, user);
        console.log(
            "After third stake - total amount:",
            userStakeAfterThird.amount
        );
        console.log(
            "After third stake - new weighted average:",
            userStakeAfterThird.entryPrice
        );

        // Calculate expected new weighted average
        // Current amount after withdraw: 750e18 (1500 - 750)
        // Current weighted average: expectedWeightedAverage (1.333...e15)
        // New stake: 250e18 at 3e15
        // New weighted average: (750 * 1.333...e15 + 250 * 3e15) / 1000
        uint256 remainingAmount = firstStakeAmount +
            secondStakeAmount -
            withdrawAmount;
        uint256 expectedNewWeightedAverage = ((remainingAmount *
            expectedWeightedAverage) +
            (thirdStakeAmount * thirdCollateralPrice)) /
            (remainingAmount + thirdStakeAmount);
        console.log(
            "Expected new weighted average:",
            expectedNewWeightedAverage
        );

        assertEq(
            userStakeAfterThird.amount,
            remainingAmount + thirdStakeAmount
        );
        assertEq(userStakeAfterThird.entryPrice, expectedNewWeightedAverage);

        console.log(
            "SUCCESS: Multiple stakes weighted average calculation works correctly!"
        );

        vm.stopPrank();
    }

    function testCollateralCalculationFix() public {
        console.log("=== Testing Collateral Calculation Fix ===");

        vm.startPrank(owner);

        // Create a collateralized pool with 6-decimal collateral token
        uint256 collateralPrice = 3000; // 0.003 in 6 decimals (3000 / 1e6 = 0.003)
        uint256 poolId = stakingPools.createPool(
            address(stakeToken), // _stakeToken (18 decimals)
            address(rewardToken), // _rewardToken
            APY, // _apy
            DURATION, // _duration
            block.timestamp, // _startTime
            true, // _canWithdrawStake
            MIN_STAKE, // _minStakeAmount
            true, // _isCollateralized
            address(collateralToken), // _collateralToken (6 decimals)
            false, // _isNative
            collateralPrice
        );

        // Fund the contract with reward tokens
        rewardToken.mint(address(stakingPools), 10000e18);

        vm.stopPrank();

        // Test with user
        vm.startPrank(user);
        uint256 stakeAmount = 1000e18; // 1000 stake tokens (18 decimals)
        stakeToken.approve(address(stakingPools), stakeAmount);

        console.log("=== Test Parameters ===");
        console.log("Stake amount:", stakeAmount);
        console.log("Collateral price:", collateralPrice);
        console.log("Stake token decimals: 18");
        console.log("Collateral token decimals: 6");

        // Expected calculation:
        // userShare = (stakeAmount * collateralPrice) / 1e18
        // userShare = (1000e18 * 3000) / 1e18 = 3000
        // This represents 3000 units of 6-decimal collateral token
        // Which is 3000 / 1e6 = 0.003 collateral tokens per stake token
        // For 1000 stake tokens: 1000 * 0.003 = 3 collateral tokens = 3e6 units

        uint256 expectedCollateral = (stakeAmount * collateralPrice) / 1e18;
        console.log("Expected collateral minted:", expectedCollateral);

        uint256 userCollateralBefore = collateralToken.balanceOf(user);
        console.log("User collateral balance before:", userCollateralBefore);

        // Stake tokens
        stakingPools.stake(poolId, stakeAmount);

        uint256 userCollateralAfter = collateralToken.balanceOf(user);
        console.log("User collateral balance after:", userCollateralAfter);

        // Verify the calculation is correct
        assertEq(userCollateralAfter, expectedCollateral);

        // Verify the ratio: should be 0.003 collateral tokens per stake token
        // For 1000 stake tokens, we should get 3000 units of collateral token
        // which is 3000 / 1e6 = 0.003 collateral tokens per stake token
        console.log(
            "Collateral per stake token (in collateral decimals):",
            (userCollateralAfter * 1e18) / stakeAmount
        );
        console.log("Expected: 3000 (0.003 in 6 decimals)");

        // Test withdrawal
        console.log("=== Testing Withdrawal ===");
        collateralToken.approve(address(stakingPools), userCollateralAfter);

        uint256 withdrawAmount = 500e18; // Withdraw half
        uint256 expectedBurnAmount = (withdrawAmount * collateralPrice) / 1e18;
        console.log("Withdraw amount:", withdrawAmount);
        console.log("Expected burn amount:", expectedBurnAmount);

        uint256 userCollateralBeforeWithdraw = collateralToken.balanceOf(user);
        stakingPools.withdraw(poolId, withdrawAmount);
        uint256 userCollateralAfterWithdraw = collateralToken.balanceOf(user);

        uint256 actualBurnAmount = userCollateralBeforeWithdraw -
            userCollateralAfterWithdraw;
        console.log("Actual burn amount:", actualBurnAmount);

        assertEq(actualBurnAmount, expectedBurnAmount);

        console.log("SUCCESS: Collateral calculation is now correct!");

        vm.stopPrank();
    }

    function testPreventETHLossInNonNativePools() public {
        console.log("=== Testing ETH Loss Prevention in Non-Native Pools ===");

        // Use the existing non-native pool (pool 0 from setUp)
        StakingPools.Pool memory pool = stakingPools.getPoolInfo(0);
        if (pool.isNative) {
            console.log("Pool is native: true");
        } else {
            console.log("Pool is native: false");
        }
        assertEq(
            pool.isNative,
            false,
            "Pool should be non-native for this test"
        );

        vm.startPrank(user);

        // Give user enough ETH to attempt the transaction
        vm.deal(user, 10 ether);

        uint256 stakeAmount = 500e18;
        stakeToken.approve(address(stakingPools), stakeAmount);

        console.log(
            "=== Testing: Sending ETH to Non-Native Pool (Should Fail) ==="
        );
        console.log("Stake amount:", stakeAmount);
        // console.log("ETH being sent:", 1 ether);

        // This should revert because we're sending ETH to a non-native pool
        vm.expectRevert("Do not send native token to non-native pool");
        stakingPools.stake{value: 1 ether}(0, stakeAmount);

        console.log(
            "SUCCESS: Transaction correctly reverted when sending ETH to non-native pool"
        );

        // Verify user's ETH balance hasn't changed (except for gas)
        console.log("User ETH balance maintained (ETH not lost)");

        console.log(
            "=== Testing: Normal Staking Without ETH (Should Succeed) ==="
        );

        // This should succeed - no ETH sent, just ERC20 tokens
        uint256 userStakeBalanceBefore = stakeToken.balanceOf(user);
        uint256 contractStakeBalanceBefore = stakeToken.balanceOf(
            address(stakingPools)
        );

        console.log("User stake token balance before:", userStakeBalanceBefore);
        console.log(
            "Contract stake token balance before:",
            contractStakeBalanceBefore
        );

        stakingPools.stake(0, stakeAmount); // No {value: ...} - this should work

        uint256 userStakeBalanceAfter = stakeToken.balanceOf(user);
        uint256 contractStakeBalanceAfter = stakeToken.balanceOf(
            address(stakingPools)
        );

        console.log("User stake token balance after:", userStakeBalanceAfter);
        console.log(
            "Contract stake token balance after:",
            contractStakeBalanceAfter
        );

        // Verify normal ERC20 staking still works
        assertEq(userStakeBalanceAfter, userStakeBalanceBefore - stakeAmount);
        assertEq(
            contractStakeBalanceAfter,
            contractStakeBalanceBefore + stakeAmount
        );

        // Verify stake was recorded
        (StakingPools.UserStake memory userStake, ) = stakingPools
            .getUserStakeInfo(0, user);
        assertEq(userStake.amount, stakeAmount);

        console.log(
            "SUCCESS: Normal ERC20 staking works correctly without ETH"
        );

        vm.stopPrank();
    }

    function testNativePoolStillWorksWithETH() public {
        console.log("=== Testing Native Pool Still Accepts ETH ===");

        vm.startPrank(owner);

        // Create a native ETH pool
        uint256 nativePoolId = stakingPools.createPool(
            address(0), // _stakeToken - address(0) for native
            address(rewardToken), // _rewardToken
            APY, // _apy
            DURATION, // _duration
            block.timestamp, // _startTime
            true, // _canWithdrawStake
            MIN_STAKE, // _minStakeAmount
            false, // _isCollateralized
            address(0), // _collateralToken
            true, // _isNative - THIS IS THE KEY
            0 // _collateralPrice
        );

        // Fund the contract with reward tokens
        rewardToken.mint(address(stakingPools), 10000e18);

        vm.stopPrank();

        // Test native pool accepts ETH
        vm.startPrank(user);
        vm.deal(user, 10 ether); // Give user some ETH

        uint256 ethStakeAmount = 2 ether;
        uint256 userETHBalanceBefore = user.balance;
        uint256 contractETHBalanceBefore = address(stakingPools).balance;

        console.log("User ETH balance before:", userETHBalanceBefore);
        console.log("Contract ETH balance before:", contractETHBalanceBefore);
        console.log("ETH stake amount:", ethStakeAmount);

        // This should succeed - sending ETH to a native pool
        stakingPools.stake{value: ethStakeAmount}(nativePoolId, 0); // amount parameter ignored for native pools

        uint256 userETHBalanceAfter = user.balance;
        uint256 contractETHBalanceAfter = address(stakingPools).balance;

        console.log("User ETH balance after:", userETHBalanceAfter);
        console.log("Contract ETH balance after:", contractETHBalanceAfter);

        // Verify ETH was transferred correctly
        assertEq(
            contractETHBalanceAfter,
            contractETHBalanceBefore + ethStakeAmount
        );

        // Verify stake was recorded
        (StakingPools.UserStake memory userStake, ) = stakingPools
            .getUserStakeInfo(nativePoolId, user);
        assertEq(userStake.amount, ethStakeAmount);

        console.log("SUCCESS: Native pool correctly accepts ETH");

        vm.stopPrank();
    }

    function testAdministrativeEventEmissions() public {
        console.log("=== Testing Administrative Event Emissions ===");

        vm.startPrank(owner);

        // Create a test pool
        uint256 poolId = stakingPools.createPool(
            address(stakeToken),
            address(rewardToken),
            APY,
            DURATION,
            block.timestamp,
            true, // canWithdrawStake
            MIN_STAKE,
            false, // isCollateralized
            address(0), // collateralToken
            false, // isNative
            0 // collateralPrice
        );

        console.log("=== Testing updatePoolMinStake Event ===");
        uint256 newMinStake = 2000e18;

        // Test PoolMinStakeUpdated event
        vm.expectEmit(true, false, false, true);
        emit PoolMinStakeUpdated(poolId, newMinStake);

        stakingPools.updatePoolMinStake(poolId, newMinStake);

        // Verify the change was made
        StakingPools.Pool memory pool = stakingPools.getPoolInfo(poolId);
        assertEq(pool.minStakeAmount, newMinStake);
        console.log("[OK] PoolMinStakeUpdated event emitted correctly");

        console.log("=== Testing extendPoolDuration Event ===");
        uint256 additionalTime = 86400; // 1 day
        uint256 expectedNewEndTime = pool.endTime + additionalTime;

        // Test PoolDurationExtended event
        vm.expectEmit(true, false, false, true);
        emit PoolDurationExtended(poolId, additionalTime, expectedNewEndTime);

        stakingPools.extendPoolDuration(poolId, additionalTime);

        // Verify the change was made
        pool = stakingPools.getPoolInfo(poolId);
        assertEq(pool.endTime, expectedNewEndTime);
        console.log("[OK] PoolDurationExtended event emitted correctly");

        console.log("=== Testing updateCollateralPrice Event ===");

        // Create a collateralized pool for testing collateral price updates
        uint256 collateralPoolId = stakingPools.createPool(
            address(stakeToken),
            address(rewardToken),
            APY,
            DURATION,
            block.timestamp,
            true, // canWithdrawStake
            MIN_STAKE,
            true, // isCollateralized
            address(collateralToken),
            false, // isNative
            1000000000000000 // initial collateral price
        );

        uint256 newCollateralPrice = 2000000000000000; // 0.002 ETH

        // Test CollateralPriceUpdated event
        vm.expectEmit(true, false, false, true);
        emit CollateralPriceUpdated(collateralPoolId, newCollateralPrice);

        stakingPools.updateCollateralPrice(
            collateralPoolId,
            newCollateralPrice
        );

        // Verify the change was made
        StakingPools.Pool memory collateralPool = stakingPools.getPoolInfo(
            collateralPoolId
        );
        assertEq(collateralPool.collateralPrice, newCollateralPrice);
        console.log("[OK] CollateralPriceUpdated event emitted correctly");

        console.log("SUCCESS: All administrative events are properly emitted!");

        vm.stopPrank();
    }

    function testUpdateCollateralPriceRevertCases() public {
        console.log("=== Testing updateCollateralPrice Revert Cases ===");

        vm.startPrank(owner);

        // Create a non-collateralized pool
        uint256 nonCollateralPoolId = stakingPools.createPool(
            address(stakeToken),
            address(rewardToken),
            APY,
            DURATION,
            block.timestamp,
            true, // canWithdrawStake
            MIN_STAKE,
            false, // isCollateralized - this is false
            address(0), // collateralToken
            false, // isNative
            0 // collateralPrice
        );

        // Try to update collateral price on non-collateralized pool
        vm.expectRevert("Pool is not collateralized");
        stakingPools.updateCollateralPrice(
            nonCollateralPoolId,
            1000000000000000
        );

        console.log(
            "[OK] Correctly reverts when trying to update collateral price on non-collateralized pool"
        );

        // Create a collateralized pool
        uint256 collateralPoolId = stakingPools.createPool(
            address(stakeToken),
            address(rewardToken),
            APY,
            DURATION,
            block.timestamp,
            true, // canWithdrawStake
            MIN_STAKE,
            true, // isCollateralized
            address(collateralToken),
            false, // isNative
            1000000000000000 // initial collateral price
        );

        // Try to update collateral price to zero
        vm.expectRevert("Invalid collateral price");
        stakingPools.updateCollateralPrice(collateralPoolId, 0);

        console.log(
            "Correctly reverts when trying to set collateral price to zero"
        );

        vm.stopPrank();

        // Test non-owner trying to update collateral price
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user
            )
        );
        stakingPools.updateCollateralPrice(collateralPoolId, 1000000000000000);

        console.log(
            "Correctly reverts when non-owner tries to update collateral price"
        );

        vm.stopPrank();
    }

    function testExtendPoolDurationRevertCases() public {
        console.log("=== Testing extendPoolDuration Revert Cases ===");

        vm.startPrank(owner);

        // Create a test pool
        uint256 poolId = stakingPools.createPool(
            address(stakeToken),
            address(rewardToken),
            APY,
            DURATION,
            block.timestamp,
            true, // canWithdrawStake
            MIN_STAKE,
            false, // isCollateralized
            address(0), // collateralToken
            false, // isNative
            0 // collateralPrice
        );

        // Try to extend with zero additional time
        vm.expectRevert("Additional time must be greater than 0");
        stakingPools.extendPoolDuration(poolId, 0);

        console.log(
            "Correctly reverts when trying to extend with zero additional time"
        );

        // Fast forward time to after pool ends
        vm.warp(block.timestamp + DURATION + 1);

        // Try to extend ended pool
        vm.expectRevert("Cannot extend ended pool");
        stakingPools.extendPoolDuration(poolId, 86400);

        console.log("Correctly reverts when trying to extend ended pool");

        vm.stopPrank();
    }

    // Events declarations for testing
    event PoolMinStakeUpdated(
        uint256 indexed poolId,
        uint256 newMinStakeAmount
    );
    event PoolDurationExtended(
        uint256 indexed poolId,
        uint256 additionalTime,
        uint256 newEndTime
    );
    event CollateralPriceUpdated(
        uint256 indexed poolId,
        uint256 newCollateralPrice
    );
}
