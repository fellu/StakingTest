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
    uint256 public minimumStakeAmount;
    address public feeAddress;

    struct PoolInfo {
        uint256 lockupDuration;
        uint256 multiplier;
        uint256 penaltyAmount;
        bool withdrawWithPenalty;
        bool active;
        bool requireMinimumStake;
    }

    struct StakeInfo {
        uint256 amount;
        uint256 startTime;
        uint256 endTime;
        uint256 rewardPerTokenPaid;
        uint256 rewards;
    }

    PoolInfo[] public pools;
    mapping(address => mapping(uint256 => StakeInfo)) public userStakes;

    uint256 public totalSupply;
    mapping(address => uint256) private _balances;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _stakingToken,
        address _rewardsToken,
        uint256 _rewardsDuration,
        address _feeAddress
    ) {
        stakingToken = IERC20(_stakingToken);
        rewardsToken = IERC20(_rewardsToken);
        rewardsDuration = _rewardsDuration;
        minimumStakeAmount = 999_999 * 10**18;
        feeAddress = _feeAddress;

        pools.push(PoolInfo(90 days, 0.5 * 1e1, 30, true, true, true)); // 90 days, 0.5x multiplier
        pools.push(PoolInfo(180 days, 1 * 1e1, 30, true, true, true)); // 180 days, 1x multiplier
        pools.push(PoolInfo(360 days, 1.5 * 1e1, 30, true, true, true)); // 360 days, 1.5x multiplier
        pools.push(PoolInfo(360 days, 1.5 * 1e1, 100, false, true, false)); // 360 days, 1.5x multiplier, cannot withdraw even with penalty
    }

    /* ========== VIEWS ========== */

    function totalSupplyAllPools() public view returns (uint256) {
        return totalSupply;
    }

    function balanceOf(address account, uint256 poolId) public view returns (uint256) {
        return userStakes[account][poolId].amount;
    }

    function balanceOf(address account) public view returns (uint256) {
        uint256 totalUserStaked = 0;
        for (uint256 i = 0; i < pools.length; i++) {
            if (i == 3) {
                uint256 campaignStake = userStakes[account][i].amount;
                if (campaignStake >= 500_000 * 10**18 && campaignStake < 1_000_000 * 10**18) {
                    totalUserStaked = totalUserStaked.add(1_000_000 * 10**18);
                } else if (campaignStake >= 2_000_000 * 10**18 && campaignStake < 3_000_000 * 10**18) {
                    totalUserStaked = totalUserStaked.add(3_000_000 * 10**18);
                } else if (campaignStake >= 7_500_000 * 10**18 && campaignStake < 10_000_000 * 10**18) {
                    totalUserStaked = totalUserStaked.add(10_000_000 * 10**18);
                } else {
                    totalUserStaked = totalUserStaked.add(campaignStake);
                }
            } else {
                totalUserStaked = totalUserStaked.add(userStakes[account][i].amount);
            }
        }
        return totalUserStaked;
    }


    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function rewardPerToken() public view returns (uint256) {
        console.log("rewardRate: ", rewardRate);
        if (totalSupply == 0) {
            return rewardPerTokenStored;
        }
        console.log("rewardPerTokenStored ", rewardPerTokenStored);
        console.log("lastTimeRewardApplicable() ", lastTimeRewardApplicable());
        console.log("lastUpdateTime ", lastUpdateTime);
        console.log("rewardRate ", rewardRate);
        console.log("totalSupply ", totalSupply);
        return
            rewardPerTokenStored.add(
              lastTimeRewardApplicable().sub(lastUpdateTime).mul(rewardRate).mul(1e18).div(totalSupply)
            );
    }

    function earned(address account, uint256 poolId) public view returns (uint256) {
        StakeInfo storage stakeInfo = userStakes[account][poolId];
        PoolInfo storage poolInfo = pools[poolId];

        // Check if the staked amount meets the minimum requirement
        if (poolInfo.requireMinimumStake && stakeInfo.amount < minimumStakeAmount) {
            return 0;
        }

        uint256 earnedRewards = stakeInfo.amount
            .mul(rewardPerToken()
            .sub(stakeInfo.rewardPerTokenPaid))
            .div(1e18)
            .add(stakeInfo.rewards)
            .div(1e1)
            .mul(poolInfo.multiplier);
        console.log("earned called for account:", account);
        console.log("poolId:", poolId);
        console.log("stakeInfo.amount:", stakeInfo.amount);
        console.log("stakeInfo.amount:", stakeInfo.amount.div(1e18));
        console.log("rewardPerToken:", rewardPerToken());
        console.log("pool multiplier:", poolInfo.multiplier);
        console.log("stakeInfo.rewardPerTokenPaid:", stakeInfo.rewardPerTokenPaid);
        console.log("stakeInfo.rewardPerTokenPaid:", stakeInfo.rewardPerTokenPaid.div(1e18));
        console.log("calculated earnedRewards:", earnedRewards);
        console.log("calculated earnedRewards:", earnedRewards.div(1e18));

        return earnedRewards;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 amount, uint256 poolId) external nonReentrant updateReward(msg.sender, poolId) {
        require(amount > 0, "Cannot stake 0");
        require(poolId < pools.length, "Invalid poolId");

        PoolInfo storage poolInfo = pools[poolId];

        require(poolInfo.active, "Pool is not active");

        totalSupply = totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        stakingToken.transferFrom(msg.sender, address(this), amount);

        StakeInfo storage stakeInfo = userStakes[msg.sender][poolId];
        stakeInfo.amount = stakeInfo.amount.add(amount);
        stakeInfo.startTime = block.timestamp;
        stakeInfo.endTime = block.timestamp.add(poolInfo.lockupDuration);
        stakeInfo.rewardPerTokenPaid = rewardPerToken();

        emit Staked(msg.sender, amount, poolId);
    }

    function stakeFor(uint256 amount, uint256 poolId, address stakeFor) external nonReentrant updateReward(msg.sender, poolId) {
        require(amount > 0, "Cannot stake 0");
        require(poolId < pools.length, "Invalid poolId");

        PoolInfo storage poolInfo = pools[poolId];

        require(poolInfo.active, "Pool is not active");

        totalSupply = totalSupply.add(amount);
        stakingToken.transferFrom(msg.sender, address(this), amount);
        _balances[stakeFor] = _balances[stakeFor].add(amount);

        StakeInfo storage stakeInfo = userStakes[stakeFor][poolId];
        stakeInfo.amount = stakeInfo.amount.add(amount);
        stakeInfo.startTime = block.timestamp;
        stakeInfo.endTime = block.timestamp.add(poolInfo.lockupDuration);
        stakeInfo.rewardPerTokenPaid = rewardPerToken();

        emit Staked(stakeFor, amount, poolId);
    }


    function withdraw(uint256 poolId) public nonReentrant updateReward(msg.sender, poolId) {
        StakeInfo storage stakeInfo = userStakes[msg.sender][poolId];
        require(stakeInfo.amount > 0, "Cannot withdraw 0");

        uint256 amount = stakeInfo.amount;
        uint256 penalty = 0;

        // Apply a penalty if withdrawing before lock period ends, or do not allow to withdraw at all
        if (block.timestamp < stakeInfo.endTime) {
            PoolInfo storage poolInfo = pools[poolId];

            if (poolInfo.withdrawWithPenalty && poolInfo.penaltyAmount > 0) {
                penalty = amount.mul(poolInfo.penaltyAmount).div(100);
                amount = amount.sub(penalty);
            }
            else {
                require(block.timestamp >= stakeInfo.endTime, "Lock period not ended");
            }
        }


        uint256 reward = stakeInfo.rewards;

        totalSupply = totalSupply.sub(stakeInfo.amount);
        _balances[msg.sender] = _balances[msg.sender].sub(stakeInfo.amount);

        console.log("user: ", msg.sender);
        console.log("pool: ", poolId);
        console.log("amount: ", amount);
        console.log("reward: ", reward);
        stakingToken.transfer(msg.sender, amount);

        if (penalty > 0) {
            stakingToken.transfer(feeAddress, penalty);
        }

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

    function claimAllRewards() public nonReentrant {
        for (uint256 i = 0; i < pools.length; i++) {
            // Manually update rewards for each pool, not using the updateReward modifier here
            rewardPerTokenStored = rewardPerToken();
            lastUpdateTime = lastTimeRewardApplicable();

            StakeInfo storage stakeInfo = userStakes[msg.sender][i];
            stakeInfo.rewards = earned(msg.sender, i);
            stakeInfo.rewardPerTokenPaid = rewardPerTokenStored;

            // Transfer rewards if any
            uint256 reward = stakeInfo.rewards;
            if (reward > 0) {
                stakeInfo.rewards = 0;
                rewardsToken.transfer(msg.sender, reward);
                emit RewardPaid(msg.sender, reward);
            }
        }
    }


    /* ========== RESTRICTED FUNCTIONS ========== */
    function editPool(
        uint256 poolId,
        uint256 lockupDuration,
        uint256 multiplier,
        uint256 penaltyAmount,
        bool withdrawWithPenalty,
        bool active,
        bool requireMinimumStake
    ) external onlyOwner {
        require(poolId < pools.length, "Invalid poolId");

        PoolInfo storage pool = pools[poolId];
        pool.lockupDuration = lockupDuration;
        pool.multiplier = multiplier;
        pool.penaltyAmount = penaltyAmount;
        pool.withdrawWithPenalty = withdrawWithPenalty;
        pool.active = active;
        pool.requireMinimumStake = requireMinimumStake;
    }

    function setMinimumStakeAmount(uint256 _minimumStakeAmount) external onlyOwner {
        minimumStakeAmount = _minimumStakeAmount;
    }

    function emergencyWithdraw(address tokenAddress, uint256 amount) external onlyOwner {
        IERC20(tokenAddress).transfer(msg.sender, amount);
    }

    function notifyRewardAmount(uint256 reward) external onlyOwner updateReward(address(0), 0) {
        console.log("Added reward: ", reward);
        if (block.timestamp >= periodFinish) {
            rewardRate = reward.div(rewardsDuration);
            console.log("finished per rewardRate: ", rewardRate);
            console.log("finished per rewardsDuration: ", rewardsDuration);
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRate);
            rewardRate = reward.add(leftover).div(rewardsDuration);
            console.log("NOT finished per rewardRate: ", rewardRate);
        }

        uint256 highestMultiplier = 0;
        for (uint256 i = 0; i < pools.length; i++) {
            if (pools[i].multiplier > highestMultiplier) {
                highestMultiplier = pools[i].multiplier;
            }
        }

        uint256 balance = rewardsToken.balanceOf(address(this)).sub(totalStaked());
        uint256 requiredBalance = rewardRate.mul(highestMultiplier).mul(rewardsDuration).div(1e1);
        console.log("requiredBalance: ", requiredBalance);
        console.log("requiredBalance: ", requiredBalance.div(1e18));
        console.log("hadBalance: ", balance);
        console.log("hadBalance: ", balance.div(1e18));
        require(requiredBalance <= balance, "Provided reward too high");

        // Logging intermediate values
        console.log("Reward Rate:", rewardRate);
        console.log("Highest Multiplier:", highestMultiplier);
        console.log("Balance:", balance);
        console.log("Rewards Duration:", rewardsDuration);
        console.log("Required Balance:", requiredBalance);

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(rewardsDuration);
        emit RewardAdded(reward);
    }

    function addPool(
        uint256 lockupDuration,
        uint256 multiplier,
        uint256 penaltyAmount,
        bool withdrawWithPenalty,
        bool active,
        bool requireMinimumStake
    ) external onlyOwner {
        pools.push(PoolInfo({
            lockupDuration: lockupDuration,
            multiplier: multiplier,
            penaltyAmount: penaltyAmount,
            withdrawWithPenalty: withdrawWithPenalty,
            active: active,
            requireMinimumStake: requireMinimumStake
        }));
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
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        console.log("Updating rewards:");
        console.log("rewardPerTokenStored:", rewardPerTokenStored);
        console.log("lastUpdateTime:", lastUpdateTime);
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

