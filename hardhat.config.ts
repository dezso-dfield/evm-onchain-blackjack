import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-ignition"; // Ensure Ignition is included
import "@typechain/hardhat"; // Import the Typechain plugin

const config: HardhatUserConfig = {
  solidity: "0.8.20", // Match your contract's Solidity version
  networks: {
    // You can define networks here, e.g., for local development or testnets
    hardhat: {
      // This is the default Hardhat Network
      // You can configure it further if needed
    },
    localhost: {
      url: "http://127.0.0.1:8545", // Default Hardhat local node URL
    },
    // Add other networks like Sepolia, Goerli, etc., here if you plan to deploy there
    // For example:
    // sepolia: {
    //   url: process.env.SEPOLIA_RPC_URL || "",
    //   accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    // },
  },
  // Paths for artifacts, cache, and sources (optional, defaults are usually fine)
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  typechain: {
    outDir: "typechain-types", // This is the directory where types will be generated
    target: "ethers-v6",       // Or "ethers-v5" depending on your ethers version
    alwaysEmit: false,         // Only emit types if contract ABI changes
    dontOverrideCompile: false, // Allow typechain to run with hardhat compile
  },
  // Gas reporter configuration (optional)
  gasReporter: {
    enabled: (process.env.REPORT_GAS) ? true : false,
    currency: "USD",
    token: "ETH",
    gasPriceApi: "https://api.etherscan.io/api?module=proxy&action=eth_gasprice",
    coinmarketcap: process.env.COINMARKETCAP_API_KEY,
  },
};

export default config;
