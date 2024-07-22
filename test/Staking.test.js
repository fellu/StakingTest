const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Advanced Staking Contract Tests", function () {
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
        await rewardsToken.transfer(staking.target, ethers.parseEther("10000"));
    });

    it("Should deploy correctly", async function () {
        expect(await staking.target).to.properAddress;
    });

    describe("Multiple stake periods", function () {

        it("Should calculate correctly after multiple award period", async function () {
            const balanceBefore = await stakingToken.balanceOf(addr1.getAddress());

            const stakingBalanceBeforeReward = await rewardsToken.balanceOf(staking.getAddress());

            const amount50 = ethers.parseEther("50");
            const amount100 = ethers.parseEther("100");
            const amount150 = ethers.parseEther("150");

            await staking.connect(addr1).stake(amount100, 1);

            await staking.notifyRewardAmount(amount100);

            // Simulate the passage of time to accrue rewards
            await ethers.provider.send("evm_increaseTime", [rewardDuration]);
            await ethers.provider.send("evm_mine");

            const reward1 = await staking.earned(addr1.getAddress(), 1);

            console.log("\nTESTS :: reward1 before withdraw: " + reward1 + " (" +parseFloat(ethers.formatEther(reward1.toString()))+ ")")
            expect(reward1).to.gte(ethers.parseEther("99"))


            // Simulate the passage of lockup period for pools
            const pool0 = await staking.pools(0);
            const pool0LockupDuration = Number(pool0.lockupDuration);
            await ethers.provider.send("evm_increaseTime", [pool0LockupDuration]);

            // New rewards added
            console.log("\n TESTS :: Add new rewards")
            await staking.notifyRewardAmount(amount100);

            // Simulate the passage of time to accrue rewards
            await ethers.provider.send("evm_increaseTime", [rewardDuration]);
            await ethers.provider.send("evm_mine");

            const rewardAfter = await staking.earned(addr1.getAddress(), 1);

            console.log("\nTESTS :: reward after second before withdraw: " + rewardAfter + " (" +parseFloat(ethers.formatEther(rewardAfter.toString()))+ ")")
            expect(rewardAfter).to.gte(ethers.parseEther("199"))


            await staking.connect(addr2).stake(amount100, 1);
            // New rewards added
            console.log("\n TESTS :: Add new rewards")
            await staking.notifyRewardAmount(amount100);

            // Simulate the passage of time to accrue rewards
            await ethers.provider.send("evm_increaseTime", [rewardDuration]);
            await ethers.provider.send("evm_mine");

            console.log("\n TESTS :: staking.earned 1")
            const rewardAfterSecond_1 = await staking.earned(addr1.getAddress(), 1);
            console.log("\n TESTS :: staking.earned 2")
            const rewardAfterSecond_2 = await staking.earned(addr2.getAddress(), 1);

            console.log("\nTESTS :: reward after third before withdraw (addr1): " + rewardAfterSecond_1 + " (" +parseFloat(ethers.formatEther(rewardAfterSecond_1.toString()))+ ")")
            console.log("TESTS :: reward after third before withdraw (addr2): " + rewardAfterSecond_2 + " (" +parseFloat(ethers.formatEther(rewardAfterSecond_2.toString()))+ ")")



            const balance = await stakingToken.balanceOf(addr1.getAddress());
            const balanceAfterReward = await rewardsToken.balanceOf(addr1.getAddress());
            const stakingBalanceAfterReward = await rewardsToken.balanceOf(staking.getAddress());


            let preBalance = parseInt(ethers.formatEther(stakingBalanceBeforeReward.toString()))
            let afterBalance = parseInt(ethers.formatEther(stakingBalanceAfterReward.toString()))
            let balanceDiff = preBalance - afterBalance

            console.log('\nTESTS :: balanceBefore (addr1)        : ' + parseInt(ethers.formatEther(balanceBefore.toString())))
            console.log('TESTS :: balanceAfter (addr1)         : ' + parseInt(ethers.formatEther(balance.toString())))
            console.log('TESTS :: balanceAfterReward (addr1)   : ' + parseInt(ethers.formatEther(balanceAfterReward.toString())))
            console.log('TESTS :: rewards in staking (staking) : ' + parseInt(ethers.formatEther(stakingBalanceAfterReward.toString())))
            console.log('TESTS ::     before staking (staking) : ' + parseInt(ethers.formatEther(stakingBalanceBeforeReward.toString())))
            console.log('TESTS :: diff in staking              : ' + balanceDiff)


            //expect(balance).to.equal(ethers.parseEther("1000"));
        });


    });
});

