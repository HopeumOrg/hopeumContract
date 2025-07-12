// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {StakingPools} from "../src/StakingPools.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract AdminEventTest is Test {
    StakingPools public stakingPools;
    MockERC20 public stakeToken;
    MockERC20 public rewardToken;
    MockERC20 public collateralToken;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    uint256 public constant APY = 500; // 5%
    uint256 public constant DURATION = 30 days;
    uint256 public constant MIN_STAKE = 1e18;

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

    function setUp() public {
        vm.startPrank(owner);

        stakingPools = new StakingPools();
        stakeToken = new MockERC20("Stake Token", "STAKE", 18);
        rewardToken = new MockERC20("Reward Token", "REWARD", 18);
        collateralToken = new MockERC20("Collateral Token", "COLLAT", 6);

        // Setup user with tokens
        stakeToken.mint(user, 2000e18);
        rewardToken.mint(address(stakingPools), 10000e18);
        collateralToken.mint(user, 1000e6);

        vm.stopPrank();
    }

    function testPoolMinStakeUpdatedEvent() public {
        vm.startPrank(owner);

        // Create a pool
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

        uint256 newMinStake = 2000e18;

        // Expect the event to be emitted
        vm.expectEmit(true, false, false, true);
        emit PoolMinStakeUpdated(poolId, newMinStake);

        stakingPools.updatePoolMinStake(poolId, newMinStake);

        // Verify the change was made
        StakingPools.Pool memory pool = stakingPools.getPoolInfo(poolId);
        assertEq(pool.minStakeAmount, newMinStake);

        vm.stopPrank();
    }

    function testPoolDurationExtendedEvent() public {
        vm.startPrank(owner);

        // Create a pool
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

        uint256 additionalTime = 86400; // 1 day
        StakingPools.Pool memory poolBefore = stakingPools.getPoolInfo(poolId);
        uint256 expectedNewEndTime = poolBefore.endTime + additionalTime;

        // Expect the event to be emitted
        vm.expectEmit(true, false, false, true);
        emit PoolDurationExtended(poolId, additionalTime, expectedNewEndTime);

        stakingPools.extendPoolDuration(poolId, additionalTime);

        // Verify the change was made
        StakingPools.Pool memory poolAfter = stakingPools.getPoolInfo(poolId);
        assertEq(poolAfter.endTime, expectedNewEndTime);

        vm.stopPrank();
    }

    function testCollateralPriceUpdatedEvent() public {
        vm.startPrank(owner);

        // Create a collateralized pool
        uint256 poolId = stakingPools.createPool(
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

        // Expect the event to be emitted
        vm.expectEmit(true, false, false, true);
        emit CollateralPriceUpdated(poolId, newCollateralPrice);

        stakingPools.updateCollateralPrice(poolId, newCollateralPrice);

        // Verify the change was made
        StakingPools.Pool memory pool = stakingPools.getPoolInfo(poolId);
        assertEq(pool.collateralPrice, newCollateralPrice);

        vm.stopPrank();
    }

    function testAllAdministrativeEventsWork() public {
        vm.startPrank(owner);

        // Create pools for testing
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

        // Test all events are emitted
        vm.expectEmit(true, false, false, true);
        emit PoolMinStakeUpdated(poolId, 3000e18);
        stakingPools.updatePoolMinStake(poolId, 3000e18);

        vm.expectEmit(true, false, false, true);
        emit PoolDurationExtended(
            poolId,
            86400,
            block.timestamp + DURATION + 86400
        );
        stakingPools.extendPoolDuration(poolId, 86400);

        vm.expectEmit(true, false, false, true);
        emit CollateralPriceUpdated(collateralPoolId, 5000000000000000);
        stakingPools.updateCollateralPrice(collateralPoolId, 5000000000000000);

        console.log("SUCCESS: All administrative events working correctly!");

        vm.stopPrank();
    }
}
