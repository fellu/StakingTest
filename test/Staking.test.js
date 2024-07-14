const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Staking Contract", function () {
    let Staking, staking, rewardsToken, stakingToken, owner, addr1, addr2;
    const rewardDuration = 60 * 60 * 24 * 30; // 30 days

    beforeEach(async function () {
        [owner, addr1, addr2] = await ethers.getSigners();

        // Deploy a mock ERC20 token for rewards
        const ERC20Mock = await ethers.getContractFactory("ERC20Mock");
        rewardsToken = await ERC20Mock.deploy("Rewards Token", "RWT", ethers.parseEther("1000000"));
        await rewardsToken.waitForDeployment();

        // Deploy a mock ERC20 token for staking
        stakingToken = await ERC20Mock.deploy("Staking Token", "STK", ethers.parseEther("1000000"));
        await stakingToken.waitForDeployment();

        // Deploy the Staking contract
        Staking = await ethers.getContractFactory("Staking");
        staking = await Staking.deploy(stakingToken.target, rewardsToken.target, rewardDuration);
        await staking.waitForDeployment();

        // Transfer some tokens to addr1 and addr2
        await stakingToken.transfer(addr1.getAddress(), ethers.parseEther("1000"));
        await stakingToken.transfer(addr2.getAddress(), ethers.parseEther("1000"));

        // Approve the staking contract to spend tokens on behalf of addr1 and addr2
        await stakingToken.connect(addr1).approve(staking.target, ethers.parseEther("1000"));
        await stakingToken.connect(addr2).approve(staking.target, ethers.parseEther("1000"));

        // Transfer some rewards to the staking contract
        await rewardsToken.transfer(staking.target, ethers.parseEther("1000"));
    });

    it("Should deploy correctly", async function () {
        expect(await staking.target).to.properAddress;
    });

    describe("Staking and Reward Mechanics", function () {
        it("Should stake tokens in the correct pool", async function () {
            const amount = ethers.parseEther("100");
            await staking.connect(addr1).stake(amount, 0); // Stake in the first pool (90 days, 0.5x multiplier)

            const balance = await staking.balanceOf(addr1.getAddress(), 0);
            expect(balance).to.equal(amount);
        });

        it("Should update total supply per pool correctly", async function () {
            const amount = ethers.parseEther("100");
            await staking.connect(addr1).stake(amount, 0); // Stake in the first pool (90 days, 0.5x multiplier)

            const totalSupply = await staking.totalSupply(0);
            expect(totalSupply).to.equal(amount);
        });

        it("Should calculate rewards correctly", async function () {
            const stakeAmount = ethers.parseEther("100");
            const rewardAmount = ethers.parseEther("100");

            await staking.connect(addr1).stake(stakeAmount, 0);

            // Simulate the passage of time
            await ethers.provider.send("evm_increaseTime", [rewardDuration / 2]);
            await ethers.provider.send("evm_mine");

            await staking.notifyRewardAmount(rewardAmount);

            // Simulate the passage of more time to accrue rewards
            await ethers.provider.send("evm_increaseTime", [rewardDuration / 2]);
            await ethers.provider.send("evm_mine");

            const reward = await staking.earned(addr1.getAddress(), 0);
            expect(reward).to.be.gt(0);
        });

        it("Should withdraw tokens and rewards correctly after lockup period", async function () {
            const stakeAmount = ethers.parseEther("100");
            const rewardAmount = ethers.parseEther("100");

            await staking.connect(addr1).stake(stakeAmount, 0);

            // Simulate the passage of lockup period for pool 0 (90 days)
            const pool0 = await staking.pools(0);
            const pool0LockupDuration = Number(pool0.lockupDuration);
            await ethers.provider.send("evm_increaseTime", [pool0LockupDuration]);
            await ethers.provider.send("evm_mine");

            await staking.notifyRewardAmount(rewardAmount);
            await staking.connect(addr1).getReward(0);

            const userBalanceBefore = BigInt(await stakingToken.balanceOf(addr1.getAddress()));
            await staking.connect(addr1).withdraw(0);
            const userBalanceAfter = BigInt(await stakingToken.balanceOf(addr1.getAddress()));

            expect(userBalanceAfter - userBalanceBefore).to.equal(BigInt(stakeAmount));
        });

        it("Should not allow withdrawal before lockup period ends", async function () {
            const stakeAmount = ethers.parseEther("100");
            await staking.connect(addr1).stake(stakeAmount, 0);

            await expect(staking.connect(addr1).withdraw(0)).to.be.revertedWith("Lock period not ended");
        });

        it("Should handle multiple pools correctly", async function () {
            const amountPool1 = ethers.parseEther("100");
            const amountPool2 = ethers.parseEther("200");

            await staking.connect(addr1).stake(amountPool1, 0); // Stake in pool 0
            await staking.connect(addr1).stake(amountPool2, 1); // Stake in pool 1

            const balancePool1 = await staking.balanceOf(addr1.getAddress(), 0);
            const balancePool2 = await staking.balanceOf(addr1.getAddress(), 1);

            expect(balancePool1).to.equal(amountPool1);
            expect(balancePool2).to.equal(amountPool2);
        });

        it("Should handle rewards distribution across multiple pools", async function () {
            const amountPool1 = ethers.parseEther("100");
            const amountPool2 = ethers.parseEther("200");
            const rewardAmount = ethers.parseEther("300");

            await staking.connect(addr1).stake(amountPool1, 0); // Stake in pool 0
            await staking.connect(addr1).stake(amountPool2, 1); // Stake in pool 1

            await staking.notifyRewardAmount(rewardAmount);

            // Simulate the passage of time to accrue rewards
            await ethers.provider.send("evm_increaseTime", [rewardDuration]);
            await ethers.provider.send("evm_mine");

            const rewardPool1 = await staking.earned(addr1.getAddress(), 0);
            const rewardPool2 = await staking.earned(addr1.getAddress(), 1);

            expect(rewardPool1).to.be.gt(0);
            expect(rewardPool2).to.be.gt(0);
        });

        it("Should revert if reward amount exceeds balance", async function () {
            await expect(staking.notifyRewardAmount(ethers.parseEther("100000000"))).to.be.revertedWith("Provided reward too high");
        });
    });

    describe("Edge Case Handling", function () {
        it("Should handle staking the minimum amount", async function () {
            const amount = ethers.parseEther("0.0001");
            await staking.connect(addr1).stake(amount, 0);

            const balance = await staking.balanceOf(addr1.getAddress(), 0);
            expect(balance).to.equal(amount);
        });

        it("Should prevent withdrawing immediately after staking", async function () {
            const amount = ethers.parseEther("100");
            await staking.connect(addr1).stake(amount, 0);

            await expect(staking.connect(addr1).withdraw(0)).to.be.revertedWith("Lock period not ended");
        });
    });
});

