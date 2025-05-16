// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {StakingPools} from "../src/StakingPools.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract StakingPoolsTest is Test {
    StakingPools public stakingPools;
    MockERC20 public stakeToken;
    MockERC20 public rewardToken;

    address public owner;
    address public user1;
    address public user2;

    uint256 public poolId;
    uint256 public constant APY = 500; // 5%
    uint256 public constant DURATION = 30 days;
    uint256 public constant INITIAL_MINT = 10000e18;
    uint256 public constant STAKE_AMOUNT = 1000e18;

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);

        // Deploy contracts
        stakingPools = new StakingPools();

        // Create tokens
        stakeToken = new MockERC20("Stake Token", "STK", 18);
        rewardToken = new MockERC20("Reward Token", "RWD", 18);

        // Mint tokens
        stakeToken.mint(owner, INITIAL_MINT);
        stakeToken.mint(user1, INITIAL_MINT);
        stakeToken.mint(user2, INITIAL_MINT);
        rewardToken.mint(owner, INITIAL_MINT);

        // Deposit reward tokens to StakingPools
        rewardToken.approve(address(stakingPools), INITIAL_MINT);
        stakingPools.depositRewardTokens(address(rewardToken), INITIAL_MINT);

        // Create a staking pool
        uint256 startTime = block.timestamp + 1 hours;
        poolId = stakingPools.createPool(
            address(stakeToken),
            address(rewardToken),
            APY,
            DURATION,
            startTime,
            true, // Allow stake withdrawal for this test pool
            0 // Minimum stake amount (0 for test)
        );
    }
    // 1000.000000000000000000
    // 8.219178082191780821

    function test_Constructor() public view {
        assertEq(stakingPools.owner(), owner);
    }

    function test_CreatePool() public view {
        (
            address stakeTokenAddr,
            address rewardTokenAddr,
            uint256 apy,
            uint256 duration,
            ,
            ,
            ,
            bool isPaused,
            bool isActive,
            bool canWithdrawStake,
            uint256 minStakeAmount
        ) = stakingPools.pools(poolId);

        assertEq(stakeTokenAddr, address(stakeToken));
        assertEq(rewardTokenAddr, address(rewardToken));
        assertEq(apy, APY);
        assertEq(duration, DURATION);
        assertEq(isPaused, false);
        assertEq(isActive, true);
        assertEq(canWithdrawStake, true);
        assertEq(minStakeAmount, 0);
    }

    function test_PausePool() public {
        stakingPools.pausePool(poolId);
        (, , , , , , , bool isPaused, , , ) = stakingPools.pools(poolId);
        assertEq(isPaused, true);
    }

    function test_ResumePool() public {
        stakingPools.pausePool(poolId);
        stakingPools.resumePool(poolId);
        (, , , , , , , bool isPaused, , , ) = stakingPools.pools(poolId);
        assertEq(isPaused, false);
    }

    function test_ClosePool() public {
        stakingPools.closePool(poolId);
        (, , , , , , , , bool isActive, , ) = stakingPools.pools(poolId);
        assertEq(isActive, false);
    }

    function test_Stake() public {
        // Warp to start time
        (, , , , uint256 startTime, , , , , , ) = stakingPools.pools(poolId);
        vm.warp(startTime);

        // Stake tokens as user1
        vm.startPrank(user1);
        stakeToken.approve(address(stakingPools), STAKE_AMOUNT);
        stakingPools.stake(poolId, STAKE_AMOUNT);
        vm.stopPrank();

        // Check user stake
        (uint256 amount, , ) = stakingPools.userStakes(poolId, user1);
        assertEq(amount, STAKE_AMOUNT);

        // Check pool total staked
        (, , , , , , uint256 totalStaked, , , , ) = stakingPools.pools(poolId);
        assertEq(totalStaked, STAKE_AMOUNT);
    }

    function test_Withdraw() public {
        // Warp to start time and stake
        (, , , , uint256 startTime, , , , , , ) = stakingPools.pools(poolId);
        vm.warp(startTime);

        vm.startPrank(user1);
        stakeToken.approve(address(stakingPools), STAKE_AMOUNT);
        stakingPools.stake(poolId, STAKE_AMOUNT);

        // Warp forward some time
        vm.warp(startTime + 10 days);

        // Withdraw half the amount
        uint256 withdrawAmount = STAKE_AMOUNT / 2;
        stakingPools.withdraw(poolId, withdrawAmount);
        vm.stopPrank();

        // Check user stake
        (uint256 amount, , ) = stakingPools.userStakes(poolId, user1);
        assertEq(amount, STAKE_AMOUNT - withdrawAmount);

        // Check pool total staked
        (, , , , , , uint256 totalStaked, , , , ) = stakingPools.pools(poolId);
        assertEq(totalStaked, STAKE_AMOUNT - withdrawAmount);

        // Check user balance
        assertEq(
            stakeToken.balanceOf(user1),
            INITIAL_MINT - STAKE_AMOUNT + withdrawAmount
        );
    }

    function testFail_WithdrawFromLockedPool() public {
        // Create a new pool with locked stakes
        uint256 startTime = block.timestamp + 1 hours;
        uint256 lockedPoolId = stakingPools.createPool(
            address(stakeToken),
            address(rewardToken),
            APY,
            DURATION,
            startTime,
            false, // Disable stake withdrawal
            0 // Minimum stake amount
        );

        // Warp to start time and stake
        vm.warp(startTime);

        vm.startPrank(user1);
        stakeToken.approve(address(stakingPools), STAKE_AMOUNT);
        stakingPools.stake(lockedPoolId, STAKE_AMOUNT);

        // Try to withdraw - should fail
        stakingPools.withdraw(lockedPoolId, STAKE_AMOUNT);
        vm.stopPrank();
    }

    function testFail_EmergencyWithdrawFromLockedPool() public {
        // Create a new pool with locked stakes
        uint256 startTime = block.timestamp + 1 hours;
        uint256 lockedPoolId = stakingPools.createPool(
            address(stakeToken),
            address(rewardToken),
            APY,
            DURATION,
            startTime,
            false, // Disable stake withdrawal
            0 // Minimum stake amount
        );

        // Warp to start time and stake
        vm.warp(startTime);

        vm.startPrank(user1);
        stakeToken.approve(address(stakingPools), STAKE_AMOUNT);
        stakingPools.stake(lockedPoolId, STAKE_AMOUNT);

        // Try emergency withdraw - should fail
        stakingPools.emergencyWithdraw(lockedPoolId);
        vm.stopPrank();
    }

    function test_ClaimReward() public {
        // Warp to start time and stake
        (, , , , uint256 startTime, , , , , , ) = stakingPools.pools(poolId);
        vm.warp(startTime);

        vm.startPrank(user1);
        stakeToken.approve(address(stakingPools), STAKE_AMOUNT);
        stakingPools.stake(poolId, STAKE_AMOUNT);

        // Warp forward 365 days (to make reward calculation simple)
        vm.warp(startTime + 365 days);

        // Calculate expected reward (5% of stake amount)
        uint256 expectedReward = (STAKE_AMOUNT * APY) / 10000;

        // Get initial reward token balance
        uint256 initialRewardBalance = rewardToken.balanceOf(user1);

        // Claim reward
        stakingPools.claimReward(poolId);
        vm.stopPrank();

        // Check reward token balance increased
        uint256 newRewardBalance = rewardToken.balanceOf(user1);
        assertEq(newRewardBalance - initialRewardBalance, expectedReward);
    }

    function test_EmergencyWithdraw() public {
        // Warp to start time and stake
        (, , , , uint256 startTime, , , , , , ) = stakingPools.pools(poolId);
        vm.warp(startTime);

        vm.startPrank(user1);
        stakeToken.approve(address(stakingPools), STAKE_AMOUNT);
        stakingPools.stake(poolId, STAKE_AMOUNT);

        // Emergency withdraw
        stakingPools.emergencyWithdraw(poolId);
        vm.stopPrank();

        // Check user stake is zero
        (uint256 amount, , ) = stakingPools.userStakes(poolId, user1);
        assertEq(amount, 0);

        // Check pool total staked is zero
        (, , , , , , uint256 totalStaked, , , , ) = stakingPools.pools(poolId);
        assertEq(totalStaked, 0);

        // Check user got back all staked tokens
        assertEq(stakeToken.balanceOf(user1), INITIAL_MINT);
    }

    function testFail_StakeWhenPaused() public {
        // Pause the pool
        stakingPools.pausePool(poolId);

        // Warp to start time
        (, , , , uint256 startTime, , , , , , ) = stakingPools.pools(poolId);
        vm.warp(startTime);

        // Try to stake (should fail)
        vm.startPrank(user1);
        stakeToken.approve(address(stakingPools), STAKE_AMOUNT);
        stakingPools.stake(poolId, STAKE_AMOUNT);
        vm.stopPrank();
    }

    function testFail_StakeBeforeStart() public {
        // Try to stake before start time (should fail)
        vm.startPrank(user1);
        stakeToken.approve(address(stakingPools), STAKE_AMOUNT);
        stakingPools.stake(poolId, STAKE_AMOUNT);
        vm.stopPrank();
    }

    function testFail_StakeAfterEnd() public {
        // Warp to after end time
        (, , , , uint256 startTime, uint256 endTime, , , , , ) = stakingPools
            .pools(poolId);
        vm.warp(endTime + 1);

        // Try to stake after end time (should fail)
        vm.startPrank(user1);
        stakeToken.approve(address(stakingPools), STAKE_AMOUNT);
        stakingPools.stake(poolId, STAKE_AMOUNT);
        vm.stopPrank();
    }

    function test_LockedPoolRewardCalculation() public {
        // Create a new pool with locked stakes
        uint256 startTime = block.timestamp + 1 hours;
        uint256 lockedPoolId = stakingPools.createPool(
            address(stakeToken),
            address(rewardToken),
            APY,
            DURATION,
            startTime,
            false, // Disable stake withdrawal
            0 // Minimum stake amount
        );

        // Warp to start time and stake
        vm.warp(startTime);

        vm.startPrank(user1);
        stakeToken.approve(address(stakingPools), STAKE_AMOUNT);
        stakingPools.stake(lockedPoolId, STAKE_AMOUNT);

        // Warp forward 365 days
        vm.warp(startTime + 365 days);

        // Calculate expected reward (5% of stake amount)
        uint256 expectedReward = (STAKE_AMOUNT * APY) / 10000;

        // Get initial reward token balance
        uint256 initialRewardBalance = rewardToken.balanceOf(user1);

        // Claim reward
        stakingPools.claimReward(lockedPoolId);
        vm.stopPrank();

        // Check reward token balance increased
        uint256 newRewardBalance = rewardToken.balanceOf(user1);
        assertEq(newRewardBalance - initialRewardBalance, expectedReward);
    }

    function test_MultiUserLockedPool() public {
        // Create a new pool with locked stakes
        uint256 startTime = block.timestamp + 1 hours;
        uint256 lockedPoolId = stakingPools.createPool(
            address(stakeToken),
            address(rewardToken),
            APY,
            DURATION,
            startTime,
            false, // Disable stake withdrawal
            0 // Minimum stake amount
        );

        // Warp to start time
        vm.warp(startTime);

        // User1 stakes
        vm.startPrank(user1);
        stakeToken.approve(address(stakingPools), STAKE_AMOUNT);
        stakingPools.stake(lockedPoolId, STAKE_AMOUNT);
        vm.stopPrank();

        // User2 stakes
        vm.startPrank(user2);
        stakeToken.approve(address(stakingPools), STAKE_AMOUNT);
        stakingPools.stake(lockedPoolId, STAKE_AMOUNT);
        vm.stopPrank();

        // Check total staked amount
        (, , , , , , uint256 totalStaked, , , , ) = stakingPools.pools(
            lockedPoolId
        );
        assertEq(totalStaked, STAKE_AMOUNT * 2);

        // Warp forward and check rewards for both users
        vm.warp(startTime + 365 days);

        uint256 expectedReward = (STAKE_AMOUNT * APY) / 10000;

        // User1 claims reward
        vm.startPrank(user1);
        uint256 user1InitialBalance = rewardToken.balanceOf(user1);
        stakingPools.claimReward(lockedPoolId);
        uint256 user1NewBalance = rewardToken.balanceOf(user1);
        assertEq(user1NewBalance - user1InitialBalance, expectedReward);
        vm.stopPrank();

        // User2 claims reward
        vm.startPrank(user2);
        uint256 user2InitialBalance = rewardToken.balanceOf(user2);
        stakingPools.claimReward(lockedPoolId);
        uint256 user2NewBalance = rewardToken.balanceOf(user2);
        assertEq(user2NewBalance - user2InitialBalance, expectedReward);
        vm.stopPrank();
    }

    function testFail_WithdrawAfterEndTime() public {
        // Create a new pool with locked stakes
        uint256 startTime = block.timestamp + 1 hours;
        uint256 lockedPoolId = stakingPools.createPool(
            address(stakeToken),
            address(rewardToken),
            APY,
            DURATION,
            startTime,
            false, // Disable stake withdrawal
            0 // Minimum stake amount
        );

        // Warp to start time and stake
        vm.warp(startTime);

        vm.startPrank(user1);
        stakeToken.approve(address(stakingPools), STAKE_AMOUNT);
        stakingPools.stake(lockedPoolId, STAKE_AMOUNT);

        // Warp to after end time
        vm.warp(startTime + DURATION + 1);

        // Try to withdraw - should still fail even after end time
        stakingPools.withdraw(lockedPoolId, STAKE_AMOUNT);
        vm.stopPrank();
    }

    function test_StakeTokenAReceiveTokenBRewards() public {
        // Configure a new pool where users stake TokenA and receive TokenB as rewards
        uint256 startTime = block.timestamp + 1 hours;
        uint256 tokenABPoolId = stakingPools.createPool(
            address(stakeToken), // TokenA (stake token)
            address(rewardToken), // TokenB (reward token)
            1000, // 10% APY
            90 days, // 90-day staking period
            startTime,
            true, // Allow stake withdrawal
            0 // Minimum stake amount
        );

        // Fast forward to the start time
        vm.warp(startTime);

        // User1 stakes TokenA
        uint256 stakeAmount = 1000e18;
        vm.startPrank(user1);
        stakeToken.approve(address(stakingPools), stakeAmount);
        stakingPools.stake(tokenABPoolId, stakeAmount);

        // Get initial TokenB balance for user1
        uint256 initialTokenBBalance = rewardToken.balanceOf(user1);

        // Fast forward 30 days to accrue rewards
        vm.warp(startTime + 30 days);

        // Calculate expected rewards (approximately)
        // Expected reward: amount * APY * timeElapsed / (365 days * 10000)
        uint256 timeElapsed = 30 days;
        uint256 expectedReward = (stakeAmount * 1000 * timeElapsed) /
            (365 days * 10000);

        // Claim rewards
        stakingPools.claimReward(tokenABPoolId);
        vm.stopPrank();

        // Verify user1 received TokenB as reward
        uint256 finalTokenBBalance = rewardToken.balanceOf(user1);
        uint256 actualReward = finalTokenBBalance - initialTokenBBalance;

        // Log reward information for verification
        console2.log("Expected TokenB reward:", expectedReward);
        console2.log("Actual TokenB reward:", actualReward);

        // Verify the reward is approximately correct
        assertGt(actualReward, 0, "User should receive TokenB rewards");
        assertApproxEqRel(
            actualReward,
            expectedReward,
            0.001e18,
            "Reward should be approximately expected amount"
        );

        // Verify user still has their TokenA stake
        (uint256 stakedAmount, , ) = stakingPools.userStakes(
            tokenABPoolId,
            user1
        );
        assertEq(
            stakedAmount,
            stakeAmount,
            "User's TokenA stake should remain unchanged"
        );
    }
}
