// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {StakingPools} from "../src/StakingPools.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract TokenABStakingTest is Test {
    StakingPools public stakingPools;
    MockERC20 public tokenA; // Token to be staked
    MockERC20 public tokenB; // Token to be rewarded

    address public owner;
    address public user1;
    address public user2;

    uint256 public poolId;
    uint256 public constant APY = 1000; // 10% APY (in basis points)
    uint256 public constant DURATION = 365 days;
    uint256 public constant INITIAL_MINT = 1000000e18;
    uint256 public constant STAKE_AMOUNT = 1000e18;
    uint256 public constant MIN_STAKE_AMOUNT = 100e18;

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy the StakingPools contract
        stakingPools = new StakingPools();

        // Deploy TokenA (for staking) and TokenB (for rewards)
        tokenA = new MockERC20("Stake Token A", "TKNA", 18);
        tokenB = new MockERC20("Reward Token B", "TKNB", 18);

        // Mint tokens to users and owner
        tokenA.mint(user1, INITIAL_MINT);
        tokenA.mint(user2, INITIAL_MINT);
        tokenB.mint(owner, INITIAL_MINT);

        // Deposit reward tokens to the staking pool contract
        tokenB.approve(address(stakingPools), INITIAL_MINT);
        stakingPools.depositRewardTokens(address(tokenB), INITIAL_MINT);

        // Create a staking pool where users stake TokenA and receive TokenB as rewards
        uint256 startTime = block.timestamp + 1 hours;
        poolId = stakingPools.createPool(
            address(tokenA), // Token to stake
            address(tokenB), // Token to receive as reward
            APY, // 10% APY
            DURATION, // 90 days duration
            startTime,
            true, // Allow stake withdrawal
            MIN_STAKE_AMOUNT // Minimum stake amount
        );

        // Fast forward to the pool start time
        vm.warp(startTime);
    }

    function test_StakeTokenAReceiveTokenBRewards() public {
        // User1 approves and stakes TokenA
        vm.startPrank(user1);
        tokenA.approve(address(stakingPools), STAKE_AMOUNT);
        stakingPools.stake(poolId, STAKE_AMOUNT);
        vm.stopPrank();

        // Check user1's stake
        (uint256 amount, uint256 stakedAt, uint256 lastClaimTime) = stakingPools
            .userStakes(poolId, user1);
        assertEq(
            amount,
            STAKE_AMOUNT,
            "User should have staked the correct amount of TokenA"
        );
        assertEq(
            stakedAt,
            block.timestamp,
            "Staked timestamp should be set to current time"
        );
        assertEq(
            lastClaimTime,
            block.timestamp,
            "Last claim time should be set to current time"
        );

        // Fast forward 30 days to accumulate rewards
        vm.warp(block.timestamp + 365 days);

        // Calculate expected rewards
        // Expected reward formula: amount * APY * timeElapsed / (365 days * 10000)
        uint256 timeElapsed = 365 days;
        uint256 expectedReward = (STAKE_AMOUNT * APY * timeElapsed) /
            (365 days * 10000);

        // Check pending rewards
        uint256 pendingRewards = stakingPools.calculateReward(poolId, user1);
        assertApproxEqRel(
            pendingRewards,
            expectedReward,
            0.0001e18,
            "Should calculate rewards correctly"
        );

        // Check TokenB balance before claiming
        uint256 tokenBBalanceBefore = tokenB.balanceOf(user1);
        assertEq(
            tokenBBalanceBefore,
            0,
            "User should have 0 TokenB before claiming"
        );
        // 1000.000000000000000000
        // 12.328767123287671231

        // User1 claims rewards
        vm.startPrank(user1);
        stakingPools.claimReward(poolId);
        vm.stopPrank();

        // Check TokenB balance after claiming
        uint256 tokenBBalanceAfter = tokenB.balanceOf(user1);
        assertEq(
            tokenBBalanceAfter,
            pendingRewards,
            "User should receive TokenB as rewards"
        );

        // Check TokenA stake remains unchanged
        (amount, , ) = stakingPools.userStakes(poolId, user1);
        assertEq(
            amount,
            STAKE_AMOUNT,
            "TokenA stake should remain unchanged after claiming rewards"
        );

        console2.log("=====================================================");
        console2.log("TokenA-TokenB Staking Test Results:");
        console2.log("User staked amount (TokenA):", amount);
        console2.log("Rewards received (TokenB):", tokenBBalanceAfter);
        console2.log("APY:", APY / 100, "%");
        console2.log("Time elapsed:", timeElapsed / 1 days, "days");
        console2.log("=====================================================");
    }

    function test_MultipleUsersStakingTokenAForTokenBRewards() public {
        // User1 stakes TokenA
        vm.startPrank(user1);
        tokenA.approve(address(stakingPools), STAKE_AMOUNT);
        stakingPools.stake(poolId, STAKE_AMOUNT);
        vm.stopPrank();

        // User2 stakes more TokenA
        uint256 user2StakeAmount = STAKE_AMOUNT * 2;
        vm.startPrank(user2);
        tokenA.approve(address(stakingPools), user2StakeAmount);
        stakingPools.stake(poolId, user2StakeAmount);
        vm.stopPrank();

        // Fast forward 45 days
        vm.warp(block.timestamp + 45 days);

        // Calculate expected rewards
        uint256 timeElapsed = 45 days;
        uint256 expectedReward1 = (STAKE_AMOUNT * APY * timeElapsed) /
            (365 days * 10000);
        uint256 expectedReward2 = (user2StakeAmount * APY * timeElapsed) /
            (365 days * 10000);

        // Both users claim rewards
        vm.startPrank(user1);
        stakingPools.claimReward(poolId);
        vm.stopPrank();

        vm.startPrank(user2);
        stakingPools.claimReward(poolId);
        vm.stopPrank();

        // Check TokenB balances
        uint256 user1Rewards = tokenB.balanceOf(user1);
        uint256 user2Rewards = tokenB.balanceOf(user2);

        // User2 should have twice the rewards as User1 (since they staked twice as much)
        assertApproxEqRel(
            user2Rewards,
            user1Rewards * 2,
            0.001e18,
            "User2 should have twice the rewards as User1"
        );

        console2.log("=====================================================");
        console2.log("Multiple Users Staking Test Results:");
        console2.log("User1 staked amount (TokenA):", STAKE_AMOUNT);
        console2.log("User2 staked amount (TokenA):", user2StakeAmount);
        console2.log("User1 rewards received (TokenB):", user1Rewards);
        console2.log("User2 rewards received (TokenB):", user2Rewards);
        console2.log(
            "Ratio of User2/User1 rewards:",
            uint256((user2Rewards * 100) / user1Rewards) / 100
        );
        console2.log("=====================================================");
    }

    function test_WithdrawStakedTokenAWithTokenBRewards() public {
        // User1 stakes TokenA
        vm.startPrank(user1);
        tokenA.approve(address(stakingPools), STAKE_AMOUNT);
        stakingPools.stake(poolId, STAKE_AMOUNT);

        // Fast forward 30 days
        vm.warp(block.timestamp + 30 days);

        // Check TokenA balance before withdrawal
        uint256 tokenABalanceBefore = tokenA.balanceOf(user1);

        // Withdraw half of the staked TokenA
        uint256 withdrawAmount = STAKE_AMOUNT / 2;
        stakingPools.withdraw(poolId, withdrawAmount);
        vm.stopPrank();

        // Check TokenA balance after withdrawal
        uint256 tokenABalanceAfter = tokenA.balanceOf(user1);
        assertEq(
            tokenABalanceAfter - tokenABalanceBefore,
            withdrawAmount,
            "User should receive back withdrawn TokenA"
        );

        // Check remaining stake
        (uint256 remainingStake, , ) = stakingPools.userStakes(poolId, user1);
        assertEq(
            remainingStake,
            STAKE_AMOUNT - withdrawAmount,
            "Remaining stake should be correct"
        );

        // Fast forward another 30 days (60 days total)
        vm.warp(block.timestamp + 30 days);

        // Claim rewards
        vm.startPrank(user1);
        stakingPools.claimReward(poolId);
        vm.stopPrank();

        // Check TokenB rewards received
        uint256 tokenBBalance = tokenB.balanceOf(user1);
        assertGt(tokenBBalance, 0, "User should have received TokenB rewards");

        console2.log("=====================================================");
        console2.log("Withdrawal Test Results:");
        console2.log("Initial stake (TokenA):", STAKE_AMOUNT);
        console2.log("Withdrawn amount (TokenA):", withdrawAmount);
        console2.log("Remaining stake (TokenA):", remainingStake);
        console2.log("Total rewards received (TokenB):", tokenBBalance);
        console2.log("=====================================================");
    }

    function test_UserCanStakeMultipleTimesOnSamePool() public {
        // User1 stakes first amount
        vm.startPrank(user1);
        tokenA.approve(address(stakingPools), STAKE_AMOUNT);
        stakingPools.stake(poolId, STAKE_AMOUNT);
        // Stake again with another amount
        uint256 secondStake = 500e18;
        tokenA.approve(address(stakingPools), secondStake);
        stakingPools.stake(poolId, secondStake);
        vm.stopPrank();

        // Check total staked amount
        (uint256 amount, , ) = stakingPools.userStakes(poolId, user1);
        console2.log("First stake amount:", STAKE_AMOUNT);
        console2.log("Second stake amount:", secondStake);
        console2.log("Total staked amount:", amount);
        assertEq(
            amount,
            STAKE_AMOUNT + secondStake,
            "User's total staked amount should be the sum of both stakes"
        );

        // Fast forward 30 days and check rewards accrue for total
        vm.warp(block.timestamp + 30 days);
        uint256 timeElapsed = 30 days;
        uint256 expectedReward = ((STAKE_AMOUNT + secondStake) *
            APY *
            timeElapsed) / (365 days * 10000);
        uint256 pendingRewards = stakingPools.calculateReward(poolId, user1);
        console2.log("APY:", APY / 100, "%");
        console2.log("Time elapsed:", timeElapsed / 1 days, "days");
        console2.log("Expected pending rewards:", expectedReward);
        console2.log("Actual pending rewards:", pendingRewards);
        assertApproxEqRel(
            pendingRewards,
            expectedReward,
            0.0001e18,
            "Rewards should accrue for the total staked amount"
        );
    }
}
