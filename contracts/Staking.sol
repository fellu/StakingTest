// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "hardhat/console.sol";

contract Staking is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    IERC20 public stakingToken;
    IERC20 public rewardsToken;

    uint256 public rewardsDuration;
    uint256 public periodFinish;
    uint256 public rewardRate;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    struct PoolInfo {
        uint256 lockupDuration;
        uint256 multiplier;
    }

    struct StakeInfo {
        uint256 amount;
        uint256 startTime;
        uint256 endTime;
        uint256 rewardPerTokenPaid; // Tracks user's share of rewardPerToken at the time of staking
        uint256 rewards;
    }

    PoolInfo[] public pools;
    mapping(address => mapping(uint256 => StakeInfo)) public userStakes;

    uint256 public totalSupply;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) private _balances;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _stakingToken,
        address _rewardsToken,
        uint256 _rewardsDuration
    ) {
        stakingToken = IERC20(_stakingToken);
        rewardsToken = IERC20(_rewardsToken);
        rewardsDuration = _rewardsDuration;

        pools.push(PoolInfo(90 days, 0.5 * 1e18)); // 90 days, 0.5x multiplier
        pools.push(PoolInfo(180 days, 1 * 1e18)); // 180 days, 1x multiplier
        pools.push(PoolInfo(360 days, 1.5 * 1e18)); // 360 days, 1.5x multiplier
    }

    /* ========== VIEWS ========== */

    function totalSupplyAllPools() public view returns (uint256) {
        return totalSupply;
    }

    function balanceOf(address account, uint256 poolId) public view returns (uint256) {
        return userStakes[account][poolId].amount;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken(uint256 poolId) public view returns (uint256) {
        if (totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
            lastTimeRewardApplicable().sub(lastUpdateTime).mul(rewardRate).mul(pools[poolId].multiplier).div(totalSupply)
        );
    }

    function earned(address account, uint256 poolId) public view returns (uint256) {
        return userStakes[account][poolId].amount.mul(rewardPerToken(poolId).sub(userStakes[account][poolId].rewardPerTokenPaid)).div(1e18).add(userStakes[account][poolId].rewards);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 amount, uint256 poolId) external nonReentrant updateReward(msg.sender, poolId) {
        require(amount > 0, "Cannot stake 0");
        require(poolId < pools.length, "Invalid poolId");

        totalSupply = totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        stakingToken.transferFrom(msg.sender, address(this), amount);

        StakeInfo storage stakeInfo = userStakes[msg.sender][poolId];
        stakeInfo.amount = stakeInfo.amount.add(amount);
        stakeInfo.startTime = block.timestamp;
        stakeInfo.endTime = block.timestamp.add(pools[poolId].lockupDuration);
        stakeInfo.rewardPerTokenPaid = rewardPerToken(poolId); // Store current rewardPerToken

        emit Staked(msg.sender, amount, poolId);
    }

    function withdraw(uint256 poolId) public nonReentrant updateReward(msg.sender, poolId) {
        StakeInfo storage stakeInfo = userStakes[msg.sender][poolId];
        require(stakeInfo.amount > 0, "Cannot withdraw 0");
        require(block.timestamp >= stakeInfo.endTime, "Lock period not ended");

        uint256 amount = stakeInfo.amount;
        uint256 reward = stakeInfo.rewards;

        totalSupply = totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);

        console.log("user: ", msg.sender);
        console.log("pool: ", poolId);
        console.log("amount: ", amount);
        console.log("reward: ", reward);
        stakingToken.transfer(msg.sender, amount);
        if (reward > 0) {
            stakeInfo.rewards = 0;
            rewardsToken.transfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }

        stakeInfo.amount = 0; // Mark the stake as withdrawn

        emit Withdrawn(msg.sender, amount, poolId);
    }

    function getReward(uint256 poolId) public nonReentrant updateReward(msg.sender, poolId) {
        uint256 reward = userStakes[msg.sender][poolId].rewards;
        if (reward > 0) {
            userStakes[msg.sender][poolId].rewards = 0;
            rewardsToken.transfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function exit(uint256 poolId) external {
        withdraw(poolId);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function notifyRewardAmount(uint256 reward) external onlyOwner updateReward(address(0), 0) {
        if (block.timestamp >= periodFinish) {
            rewardRate = reward.div(rewardsDuration);
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRate);
            rewardRate = reward.add(leftover).div(rewardsDuration);
        }

        uint256 balance = rewardsToken.balanceOf(address(this)).sub(totalStaked());
        uint256 highestMultiplier = 0;
        for (uint256 i = 0; i < pools.length; i++) {
            if (pools[i].multiplier > highestMultiplier) {
                highestMultiplier = pools[i].multiplier;
            }
        }

        // Corrected logic to ensure balance covers reward distribution
        uint256 requiredBalance = rewardRate.mul(highestMultiplier).mul(rewardsDuration).div(1e18);

        // Logging intermediate values
        console.log("Reward Rate:", rewardRate);
        console.log("Highest Multiplier:", highestMultiplier);
        console.log("Balance:", balance);
        console.log("Rewards Duration:", rewardsDuration);
        console.log("Required Balance:", requiredBalance);

        require(requiredBalance <= balance, "Provided reward too high");

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(rewardsDuration);
        emit RewardAdded(reward);
    }

    function addPool(uint256 lockupDuration, uint256 multiplier) external onlyOwner {
        pools.push(PoolInfo(lockupDuration, multiplier));
    }

    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
        require(block.timestamp > periodFinish, "Previous rewards period must be complete before changing the duration for the new period");
        rewardsDuration = _rewardsDuration;
    }

    function totalStaked() public view returns (uint256) {
        return totalSupply;
    }

    /* ========== MODIFIERS ========== */

    modifier updateReward(address account, uint256 poolId) {
        rewardPerTokenStored = rewardPerToken(poolId);
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            StakeInfo storage stakeInfo = userStakes[account][poolId];
            stakeInfo.rewards = earned(account, poolId);
            stakeInfo.rewardPerTokenPaid = rewardPerTokenStored;
        }
        _;
    }

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount, uint256 poolId);
    event Withdrawn(address indexed user, uint256 amount, uint256 poolId);
    event RewardPaid(address indexed user, uint256 reward);
}

