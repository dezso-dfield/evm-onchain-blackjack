    import { ethers } from "hardhat";

    async function main() {
      const CONTRACT_ADDRESS = "0x5Ec0da24DA7D2c30C75dD66c79314887f20e60A0";
      const AMOUNT_TO_FUND = ethers.parseEther("5.0");

      const [deployer] = await ethers.getSigners();

      console.log(`Funding contract ${CONTRACT_ADDRESS} with ${ethers.formatEther(AMOUNT_TO_FUND)} ETH from ${deployer.address}`);

      const tx = await deployer.sendTransaction({
        to: CONTRACT_ADDRESS,
        value: AMOUNT_TO_FUND,
      });
      await tx.wait();

      console.log("Contract funded successfully!");
      const contractBalance = await ethers.provider.getBalance(CONTRACT_ADDRESS);
      console.log(`New contract balance: ${ethers.formatEther(contractBalance)} ETH`);
    }

    main()
      .then(() => process.exit(0))
      .catch((error) => {
        console.error(error);
        process.exit(1);
      });
    