import { NetworksUserConfig } from "hardhat/src/types/config";
import * as dotenv from "dotenv";

dotenv.config();

const networks = {
  hardhat: {
    mining: {
      auto: true,
      interval: 15000
    },
    saveDeployments: true,
    accounts: [
      {
        privateKey: process.env.PRIVATE_KEY !== undefined ? process.env.PRIVATE_KEY : "",
        balance: "10000000000000000000000"
      },
      {
        privateKey: process.env.PRIVATE_KEY_TWO !== undefined ? process.env.PRIVATE_KEY_TWO : "",
        balance: "10000000000000000000000"
      }
    ],
    deploy: [ 'deploy' ]
    /* forking: {
      url: "https://polygon-mainnet.g.alchemy.com/v2/3mj-wgbscUe87OBJmuT09n-oQuK5JJLY"
    }, */
  },
  matic: {
    url: "https://polygon-mainnet.g.alchemy.com/v2/3mj-wgbscUe87OBJmuT09n-oQuK5JJLY",
    chainId: 137,
    gasPrice: 170000000000,
    accounts: process.env.PRIVATE_KEY !== undefined && process.env.PRIVATE_KEY_TWO !== undefined ? [process.env.PRIVATE_KEY, process.env.PRIVATE_KEY_TWO] : [],
    deploy: [ 'deploy/matic' ],
    saveDeployments: true,/* 
    forking: {
      url: "https://polygon-rpc.com/"
    } */
  },
  mumbai: {
    url: "https://rpc.ankr.com/polygon_mumbai",
    chainId: 80001,
    gasPrice: 170000000000,
    accounts: process.env.PRIVATE_KEY !== undefined && process.env.PRIVATE_KEY_TWO !== undefined ? [process.env.PRIVATE_KEY, process.env.PRIVATE_KEY_TWO] : [],
    deploy: [ 'deploy/mumbai' ],
    saveDeployments: true,/* 
    forking: {
      url: "https://polygon-rpc.com/"
    } */
  },
};

export default networks;