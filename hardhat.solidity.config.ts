import { MultiSolcUserConfig } from "hardhat/src/types/config";

const solidityConfiguration: MultiSolcUserConfig = {
  compilers: [
    {
      version: "0.8.17",
      settings: {
        metadata: {
          bytecodeHash: "none",
        },
        optimizer: {
          enabled: true,
          runs: 1000,
        },
      },
    },
    {
      version: "0.8.14",
      settings: {
        metadata: {
          bytecodeHash: "none",
        },
        optimizer: {
          enabled: true,
          runs: 1000,
        },
      },
    },
    {
      version: "0.6.9",
      settings: {
        metadata: {
          bytecodeHash: "none",
        },
        optimizer: {
          enabled: true,
          runs: 1000,
        },
      },
    },
  ],
  overrides: undefined
}

export default solidityConfiguration;
