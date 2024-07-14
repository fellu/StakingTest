async function main() {
    const [deployer] = await ethers.getSigners();

    console.log("Deploying contracts with the account:", deployer.address);

    const tokenAddress = "0x3553fae176cFc90826FC9c482A1c9b33afBF26f9"
    const staking = await ethers.deployContract("Staking", [tokenAddress, tokenAddress, 30]);

    console.log("Staking address:", await staking.getAddress());
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
