import * as dotenv from "dotenv";
import { HardhatUserConfig, task } from "hardhat/config";
import hardhatNetworks from "./hardhat.networks";
import solidityConfiguration from "./hardhat.solidity.config";

import "@nomicfoundation/hardhat-toolbox";  // https://www.npmjs.com/package/@nomicfoundation/hardhat-toolbox
import "@nomiclabs/hardhat-ethers";
import "solidity-coverage"
import "@typechain/hardhat"
import '@openzeppelin/hardhat-upgrades';
import "@tenderly/hardhat-tenderly"
import "hardhat-dependency-compiler";       // https://www.npmjs.com/package/hardhat-dependency-compiler
import "hardhat-storage-layout";            // https://www.npmjs.com/package/hardhat-storage-layout
import "hardhat-contract-sizer";            // https://www.npmjs.com/package/hardhat-contract-sizer
import "hardhat-abi-exporter";              // https://www.npmjs.com/package/hardhat-abi-exporter
import "hardhat-deploy-ethers";
import "hardhat-deploy";

dotenv.config();

const config: HardhatUserConfig = {
    solidity: solidityConfiguration,
    networks: hardhatNetworks,
    paths: {
      artifacts: "./artifacts",
      cache: "./cache",
      sources: "./contracts",
      tests: "./tests",
    },
    typechain: {
      outDir: "types",
      target: "ethers-v5",
    },
    gasReporter: {
      enabled: true,
      currency: "USD",
      token: "MATIC",
      //gasPrice: 1,
      /* gasPriceApi: process.env.GAS_PRICE_API,
      coinmarketcap: process.env.API_KEY */
    },
    mocha: {
      timeout: 4000000
    }
  };
  
  export default config;