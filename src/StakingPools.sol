// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IERC20Mintable {
    function mint(address to, uint256 amount) external;
}

interface IERC20Burnable {
    function burnFrom(address account, uint256 amount) external;
}

interface IERC20Metadata {
    function decimals() external view returns (uint8);
}

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
        bool isCollateralized; // true if this pool uses collateral token
        address collateralToken; // token address for the collateral token (must be mintable/burnable)
        bool isNative; // true = this pool accepts native token (ETH), false = ERC20
        uint8 collateralTokenDecimals;
        uint256 collateralPrice; // e.g., 3000000000000000 for 0.003 (if 18 decimals)
    }

    bool public globalPause;

    struct UserStake {
        uint256 amount; // Amount staked by user
        uint256 stakedAt; // Time when user staked
        uint256 lastClaimTime; // Last time rewards were claimed
        uint256 entryPrice; // Collateral price at time of staking (for collateralized pools)
    }

    uint256 public poolCount;
    mapping(uint256 => Pool) public pools;
    mapping(uint256 => mapping(address => UserStake)) public userStakes;

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
    event RewardDeposited(address rewardToken, uint256 amount);
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

    modifier notPausedGlobal() {
        require(!globalPause, "Global pause active");
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
        uint256 _minStakeAmount,
        bool _isCollateralized,
        address _collateralToken,
        bool _isNative,
        uint256 _collateralPrice
    ) external onlyOwner returns (uint256) {
        if (_isCollateralized) {
            require(_collateralToken != address(0), "Invalid collateral token");
        }

        if (_isNative) {
            require(
                _stakeToken == address(0),
                "Native token pool must use address(0)"
            );
        }
        require(
            _stakeToken != address(0) || _isNative,
            "Invalid stake token for non-native pool"
        );

        require(_rewardToken != address(0), "Invalid reward token");
        require(_apy > 0, "APY must be greater than 0");
        require(_duration > 0, "Duration must be greater than 0");
        require(
            _startTime >= block.timestamp,
            "Start time must be in the future"
        );

        // Only validate collateral price for collateralized pools
        if (_isCollateralized) {
            require(_collateralPrice > 0, "Invalid collateral price");
        }

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
            minStakeAmount: _minStakeAmount,
            isCollateralized: _isCollateralized,
            collateralToken: _isCollateralized ? _collateralToken : address(0),
            isNative: _isNative,
            collateralTokenDecimals: _isCollateralized
                ? IERC20Metadata(_collateralToken).decimals()
                : 18,
            collateralPrice: _isCollateralized ? _collateralPrice : 0
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
        emit PoolMinStakeUpdated(_poolId, _minStakeAmount);
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
        require(
            block.timestamp < pools[_poolId].endTime,
            "Cannot extend ended pool"
        );

        Pool storage pool = pools[_poolId];
        pool.duration += _additionalTime;
        pool.endTime += _additionalTime;

        emit PoolDurationExtended(_poolId, _additionalTime, pool.endTime);
    }


    function stake(
        uint256 _poolId,
        uint256 _amount
    )
        external
        payable
        nonReentrant
        poolExists(_poolId)
        poolActive(_poolId)
        notPausedGlobal
        poolNotPaused(_poolId)
    {
        Pool storage pool = pools[_poolId];
        require(block.timestamp >= pool.startTime, "Pool not started yet");
        require(block.timestamp < pool.endTime, "Pool has ended");

        // Prevent accidental ETH loss in non-native pools
        if (!pool.isNative) {
            require(
                msg.value == 0,
                "Do not send native token to non-native pool"
            );
        }

        uint256 amountToStake = pool.isNative ? msg.value : _amount;

        require(amountToStake > 0, "Amount must be greater than 0");
        require(
            amountToStake >= pool.minStakeAmount,
            "Amount below minimum stake"
        );

        UserStake storage userStake = userStakes[_poolId][msg.sender];

        // Handle token transfer
        if (pool.isNative) {
            // ETH received automatically — nothing to transfer
        } else {
            IERC20 stakeToken = IERC20(pool.stakeToken);
            stakeToken.safeTransferFrom(
                msg.sender,
                address(this),
                amountToStake
            );
        }

        // If user already has stake, claim rewards first
        if (userStake.amount > 0) {
            _claimReward(_poolId, msg.sender);
        } else {
            userStake.lastClaimTime = block.timestamp;
        }

        // Calculate weighted average entry price for collateralized pools
        if (pool.isCollateralized) {
            if (userStake.amount > 0) {
                // Calculate weighted average: (existingAmount * existingPrice + newAmount * currentPrice) / totalAmount
                uint256 totalAmount = userStake.amount + amountToStake;
                userStake.entryPrice =
                    ((userStake.amount * userStake.entryPrice) +
                        (amountToStake * pool.collateralPrice)) /
                    totalAmount;
            } else {
                // First stake, use current price
                userStake.entryPrice = pool.collateralPrice;
            }
        }

        // Update stake
        userStake.amount += amountToStake;
        userStake.stakedAt = block.timestamp;

        // Update pool total
        pool.totalStaked += amountToStake;

        // Collateralized mint
        if (pool.isCollateralized) {
            uint256 userShare = (amountToStake * pool.collateralPrice) / 1e18;
            IERC20Mintable(pool.collateralToken).mint(msg.sender, userShare);
        }

        emit Staked(_poolId, msg.sender, amountToStake);
    }

    function withdraw(
        uint256 _poolId,
        uint256 _amount
    )
        external
        nonReentrant
        poolExists(_poolId)
        notPausedGlobal
        poolNotPaused(_poolId)
    {
        Pool storage pool = pools[_poolId];
        require(pool.canWithdrawStake, "Stake withdrawal not allowed");

        UserStake storage userStake = userStakes[_poolId][msg.sender];
        require(userStake.amount >= _amount, "Insufficient staked amount");

        _claimReward(_poolId, msg.sender);

        userStake.amount -= _amount;
        pool.totalStaked -= _amount;

        if (pool.isCollateralized) {
            uint256 burnAmount = (_amount * userStake.entryPrice) / 1e18;
            IERC20Burnable(pool.collateralToken).burnFrom(
                msg.sender,
                burnAmount
            );
        }

        if (pool.isNative) {
            (bool success, ) = payable(msg.sender).call{value: _amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20 stakeToken = IERC20(pool.stakeToken);
            stakeToken.safeTransfer(msg.sender, _amount);
        }

        emit Withdrawn(_poolId, msg.sender, _amount);
    }

    function claimReward(
        uint256 _poolId
    ) external nonReentrant poolExists(_poolId) {
        _claimReward(_poolId, msg.sender);
    }

    // Loses accumulated rewards
    function emergencyWithdraw(
        uint256 _poolId
    ) external nonReentrant poolExists(_poolId) {
        Pool storage pool = pools[_poolId];
        require(pool.canWithdrawStake, "Stake withdrawal not allowed");

        UserStake storage userStake = userStakes[_poolId][msg.sender];
        require(userStake.amount > 0, "No stake to withdraw");

        uint256 amount = userStake.amount;

        userStake.amount = 0;
        pool.totalStaked -= amount;

        if (pool.isCollateralized) {
            uint256 burnAmount = (amount * userStake.entryPrice) / 1e18;
            IERC20Burnable(pool.collateralToken).burnFrom(
                msg.sender,
                burnAmount
            );
        }

        if (pool.isNative) {
            (bool success, ) = payable(msg.sender).call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20 stakeToken = IERC20(pool.stakeToken);
            stakeToken.safeTransfer(msg.sender, amount);
        }

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

        emit RewardDeposited(_rewardToken, _amount);
    }

    function withdrawRewardTokens(
        address _rewardToken,
        uint256 _amount
    ) external onlyOwner {
        require(_rewardToken != address(0), "Invalid reward token");
        require(_amount > 0, "Amount must be greater than 0");

        IERC20 token = IERC20(_rewardToken);
        require(
            token.balanceOf(address(this)) >= _amount,
            "Insufficient reward token balance"
        );

        token.safeTransfer(msg.sender, _amount);
    }

    function getRewardTokenBalance(
        address _rewardToken
    ) external view returns (uint256) {
        return IERC20(_rewardToken).balanceOf(address(this));
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
        IERC20 token = IERC20(rewardToken);
        uint256 availableReward = token.balanceOf(address(this));

        require(availableReward >= reward, "Insufficient reward token balance");

        token.safeTransfer(_user, reward);

        emit RewardClaimed(_poolId, _user, reward);
    }

    function updateCollateralPrice(
        uint256 _poolId,
        uint256 _newPrice
    ) external onlyOwner poolExists(_poolId) {
        require(pools[_poolId].isCollateralized, "Pool is not collateralized");
        require(_newPrice > 0, "Invalid collateral price");
        pools[_poolId].collateralPrice = _newPrice;
        emit CollateralPriceUpdated(_poolId, _newPrice);
    }

    function setGlobalPause(bool _paused) external onlyOwner {
        globalPause = _paused;
    }
}
