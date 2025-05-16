// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract StakingPools is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    struct Pool {
        address stakeToken; // Token to be staked
        address rewardToken; // Token to be given as reward
        uint256 apy; // Annual percentage yield (in basis points, e.g., 500 = 5%)
        uint256 duration; // Duration of the pool in seconds
        uint256 startTime; // Start time of the pool
        uint256 endTime; // End time of the pool
        uint256 totalStaked; // Total amount staked in this pool
        bool isPaused; // Whether the pool is paused
        bool isActive; // Whether the pool is active
        bool canWithdrawStake; // Whether staked tokens can be withdrawn
        uint256 minStakeAmount; // Minimum amount required to stake
    }

    struct UserStake {
        uint256 amount; // Amount staked by user
        uint256 stakedAt; // Time when user staked
        uint256 lastClaimTime; // Last time rewards were claimed
    }

    uint256 public poolCount;
    mapping(uint256 => Pool) public pools;
    mapping(uint256 => mapping(address => UserStake)) public userStakes;
    mapping(address => uint256) public rewardTokenBalances; // Track reward token balances

    // Events
    event PoolCreated(
        uint256 indexed poolId,
        address stakeToken,
        address rewardToken,
        uint256 apy,
        uint256 duration,
        uint256 minStakeAmount
    );
    event Staked(uint256 indexed poolId, address indexed user, uint256 amount);
    event Withdrawn(
        uint256 indexed poolId,
        address indexed user,
        uint256 amount
    );
    event RewardClaimed(
        uint256 indexed poolId,
        address indexed user,
        uint256 amount
    );
    event PoolPaused(uint256 indexed poolId);
    event PoolResumed(uint256 indexed poolId);
    event EmergencyWithdrawn(
        uint256 indexed poolId,
        address indexed user,
        uint256 amount
    );
    event PoolUpdated(uint256 indexed poolId, uint256 newApy);
    event PoolClosed(uint256 indexed poolId);

    constructor() Ownable(msg.sender) {}

    // Modifiers
    modifier poolExists(uint256 _poolId) {
        require(_poolId < poolCount, "Pool does not exist");
        _;
    }

    modifier poolActive(uint256 _poolId) {
        require(pools[_poolId].isActive, "Pool not active");
        _;
    }

    modifier poolNotPaused(uint256 _poolId) {
        require(!pools[_poolId].isPaused, "Pool is paused");
        _;
    }

    // Owner functions
    function createPool(
        address _stakeToken,
        address _rewardToken,
        uint256 _apy,
        uint256 _duration,
        uint256 _startTime,
        bool _canWithdrawStake,
        uint256 _minStakeAmount
    ) external onlyOwner returns (uint256) {
        require(_stakeToken != address(0), "Invalid stake token");
        require(_rewardToken != address(0), "Invalid reward token");
        require(_apy > 0, "APY must be greater than 0");
        require(_duration > 0, "Duration must be greater than 0");
        require(
            _startTime >= block.timestamp,
            "Start time must be in the future"
        );

        uint256 poolId = poolCount;
        pools[poolId] = Pool({
            stakeToken: _stakeToken,
            rewardToken: _rewardToken,
            apy: _apy,
            duration: _duration,
            startTime: _startTime,
            endTime: _startTime + _duration,
            totalStaked: 0,
            isPaused: false,
            isActive: true,
            canWithdrawStake: _canWithdrawStake,
            minStakeAmount: _minStakeAmount
        });

        poolCount++;

        emit PoolCreated(
            poolId,
            _stakeToken,
            _rewardToken,
            _apy,
            _duration,
            _minStakeAmount
        );
        return poolId;
    }

    function updatePoolAPY(
        uint256 _poolId,
        uint256 _newApy
    ) external onlyOwner poolExists(_poolId) poolActive(_poolId) {
        require(_newApy > 0, "APY must be greater than 0");
        pools[_poolId].apy = _newApy;
        emit PoolUpdated(_poolId, _newApy);
    }

    function updatePoolMinStake(
        uint256 _poolId,
        uint256 _minStakeAmount
    ) external onlyOwner poolExists(_poolId) poolActive(_poolId) {
        pools[_poolId].minStakeAmount = _minStakeAmount;
    }

    function pausePool(
        uint256 _poolId
    ) external onlyOwner poolExists(_poolId) poolActive(_poolId) {
        pools[_poolId].isPaused = true;
        emit PoolPaused(_poolId);
    }

    function resumePool(
        uint256 _poolId
    ) external onlyOwner poolExists(_poolId) poolActive(_poolId) {
        pools[_poolId].isPaused = false;
        emit PoolResumed(_poolId);
    }

    function closePool(uint256 _poolId) external onlyOwner poolExists(_poolId) {
        pools[_poolId].isActive = false;
        emit PoolClosed(_poolId);
    }

    function extendPoolDuration(
        uint256 _poolId,
        uint256 _additionalTime
    ) external onlyOwner poolExists(_poolId) poolActive(_poolId) {
        require(_additionalTime > 0, "Additional time must be greater than 0");
        Pool storage pool = pools[_poolId];
        pool.duration += _additionalTime;
        pool.endTime += _additionalTime;
    }

    // User functions
    function stake(
        uint256 _poolId,
        uint256 _amount
    )
        external
        nonReentrant
        poolExists(_poolId)
        poolActive(_poolId)
        poolNotPaused(_poolId)
    {
        Pool storage pool = pools[_poolId];
        require(block.timestamp >= pool.startTime, "Pool not started yet");
        require(block.timestamp < pool.endTime, "Pool has ended");
        require(_amount > 0, "Amount must be greater than 0");
        require(_amount >= pool.minStakeAmount, "Amount below minimum stake");

        UserStake storage userStake = userStakes[_poolId][msg.sender];

        // Transfer tokens from user to this contract using SafeERC20
        IERC20 stakeToken = IERC20(pool.stakeToken);
        stakeToken.safeTransferFrom(msg.sender, address(this), _amount);

        // If user already has a stake, claim rewards first
        if (userStake.amount > 0) {
            _claimReward(_poolId, msg.sender);
        } else {
            // Initialize new stake
            userStake.lastClaimTime = block.timestamp;
        }

        // Update user stake
        userStake.amount += _amount;
        userStake.stakedAt = block.timestamp;

        // Update pool total staked
        pool.totalStaked += _amount;

        emit Staked(_poolId, msg.sender, _amount);
    }

    function withdraw(
        uint256 _poolId,
        uint256 _amount
    ) external nonReentrant poolExists(_poolId) poolNotPaused(_poolId) {
        Pool storage pool = pools[_poolId];
        require(pool.canWithdrawStake, "Stake withdrawal not allowed");
        UserStake storage userStake = userStakes[_poolId][msg.sender];
        require(userStake.amount >= _amount, "Insufficient staked amount");

        // Claim rewards before withdrawal
        _claimReward(_poolId, msg.sender);

        // Update user stake
        userStake.amount -= _amount;

        // Update pool total staked
        pool.totalStaked -= _amount;

        // Transfer tokens back to user using SafeERC20
        IERC20 stakeToken = IERC20(pool.stakeToken);
        stakeToken.safeTransfer(msg.sender, _amount);

        emit Withdrawn(_poolId, msg.sender, _amount);
    }

    function claimReward(
        uint256 _poolId
    ) external nonReentrant poolExists(_poolId) {
        _claimReward(_poolId, msg.sender);
    }

    function emergencyWithdraw(
        uint256 _poolId
    ) external nonReentrant poolExists(_poolId) {
        Pool storage pool = pools[_poolId];
        require(pool.canWithdrawStake, "Stake withdrawal not allowed");
        UserStake storage userStake = userStakes[_poolId][msg.sender];
        require(userStake.amount > 0, "No stake to withdraw");

        uint256 amount = userStake.amount;

        // Reset user stake first to prevent reentrancy
        userStake.amount = 0;

        // Update pool total staked
        pool.totalStaked -= amount;

        // Transfer tokens back to user using SafeERC20
        IERC20 stakeToken = IERC20(pool.stakeToken);
        stakeToken.safeTransfer(msg.sender, amount);

        emit EmergencyWithdrawn(_poolId, msg.sender, amount);
    }

    // View functions
    function getPoolInfo(
        uint256 _poolId
    ) external view poolExists(_poolId) returns (Pool memory) {
        return pools[_poolId];
    }

    function getUserStakeInfo(
        uint256 _poolId,
        address _user
    )
        external
        view
        poolExists(_poolId)
        returns (UserStake memory, uint256 pendingRewards)
    {
        UserStake memory userStake = userStakes[_poolId][_user];
        uint256 rewards = calculateReward(_poolId, _user);
        return (userStake, rewards);
    }

    function calculateReward(
        uint256 _poolId,
        address _user
    ) public view poolExists(_poolId) returns (uint256) {
        UserStake storage userStake = userStakes[_poolId][_user];
        if (userStake.amount == 0) {
            return 0;
        }

        Pool storage pool = pools[_poolId];

        // Calculate time elapsed since last claim or since staking if never claimed
        uint256 endCalculationTime = block.timestamp;
        if (endCalculationTime > pool.endTime) {
            endCalculationTime = pool.endTime;
        }

        uint256 startCalculationTime = userStake.lastClaimTime;
        if (startCalculationTime < pool.startTime) {
            startCalculationTime = pool.startTime;
        }

        if (startCalculationTime >= endCalculationTime) {
            return 0;
        }

        uint256 timeElapsed = endCalculationTime - startCalculationTime;

        // Calculate reward: amount * APY * timeElapsed / (365 days * 10000)
        // APY is in basis points (e.g., 500 = 5%)
        uint256 reward = (userStake.amount * pool.apy * timeElapsed) /
            (365 days * 10000);

        return reward;
    }

    // Function to get all active pools
    function getActivePools() external view returns (uint256[] memory) {
        uint256 activeCount = 0;

        // First count active pools
        for (uint256 i = 0; i < poolCount; i++) {
            if (pools[i].isActive) {
                activeCount++;
            }
        }

        // Then populate the array
        uint256[] memory activePools = new uint256[](activeCount);
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < poolCount; i++) {
            if (pools[i].isActive) {
                activePools[currentIndex] = i;
                currentIndex++;
            }
        }

        return activePools;
    }

    // Owner functions for reward management
    function depositRewardTokens(
        address _rewardToken,
        uint256 _amount
    ) external onlyOwner {
        require(_rewardToken != address(0), "Invalid reward token");
        require(_amount > 0, "Amount must be greater than 0");

        IERC20 token = IERC20(_rewardToken);
        token.safeTransferFrom(msg.sender, address(this), _amount);

        rewardTokenBalances[_rewardToken] += _amount;
    }

    function withdrawRewardTokens(
        address _rewardToken,
        uint256 _amount
    ) external onlyOwner {
        require(_rewardToken != address(0), "Invalid reward token");
        require(_amount > 0, "Amount must be greater than 0");
        require(
            rewardTokenBalances[_rewardToken] >= _amount,
            "Insufficient reward token balance"
        );

        rewardTokenBalances[_rewardToken] -= _amount;

        IERC20 token = IERC20(_rewardToken);
        token.safeTransfer(msg.sender, _amount);
    }

    function getRewardTokenBalance(
        address _rewardToken
    ) external view returns (uint256) {
        return rewardTokenBalances[_rewardToken];
    }

    // Emergency function to recover ERC20 tokens sent to contract by mistake
    function recoverERC20(address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(owner(), _amount);
    }

    // Internal functions
    function _claimReward(uint256 _poolId, address _user) internal {
        UserStake storage userStake = userStakes[_poolId][_user];
        if (userStake.amount == 0) {
            return;
        }

        uint256 reward = calculateReward(_poolId, _user);
        if (reward == 0) {
            // Update last claim time even if reward is 0
            userStake.lastClaimTime = block.timestamp;
            return;
        }

        // Update last claim time
        userStake.lastClaimTime = block.timestamp;

        // Get reward token address
        address rewardToken = pools[_poolId].rewardToken;

        // Check if contract has enough reward tokens
        require(
            rewardTokenBalances[rewardToken] >= reward,
            "Insufficient reward token balance"
        );

        // Update reward token balance
        rewardTokenBalances[rewardToken] -= reward;

        // Transfer reward tokens using SafeERC20
        IERC20 token = IERC20(rewardToken);
        token.safeTransfer(_user, reward);

        emit RewardClaimed(_poolId, _user, reward);
    }
}
