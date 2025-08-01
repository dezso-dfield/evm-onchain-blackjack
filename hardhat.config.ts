import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox"; // Or whatever plugins you use

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.20", // Your current Solidity version
    settings: {
      optimizer: {
        enabled: true,
        runs: 200, // Common value. Higher runs mean more optimization but longer compile times.
                  // For deployment, a lower value like 200 is often good to find a balance.
      },
      // You can also consider turning off revert strings if space is extremely tight,
      // but this makes debugging much harder. Only do this if absolutely necessary.
      // debug: {
      //   // This setting (part of debug) affects revert strings
      //   // See https://docs.soliditylang.org/en/latest/using-the-compiler.html#compiler-flags
      //   revertStrings: false,
      // }
    },
  },
  networks: {
    // Your network configurations if any
    hardhat: {
      // Hardhat Network specific configurations
    },
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  typechain: {
    outDir: "typechain-types",
    target: "ethers-v6",
  },
};

export default config;