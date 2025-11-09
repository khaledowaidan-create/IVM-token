require("dotenv").config();
require("@nomicfoundation/hardhat-toolbox");

const {
  PRIVATE_KEY,
  SEPOLIA_RPC_URL,
  MAINNET_RPC_URL,
  ETHERSCAN_API_KEY,
} = process.env;

if (!SEPOLIA_RPC_URL) {
  throw new Error("Missing SEPOLIA_RPC_URL in .env");
}
if (!PRIVATE_KEY) {
  throw new Error("Missing PRIVATE_KEY in .env");
}

const normalizedPrivateKey = PRIVATE_KEY.startsWith("0x")
  ? PRIVATE_KEY
  : `0x${PRIVATE_KEY}`;
const accounts = [normalizedPrivateKey];

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: { enabled: true, runs: 200 },
    },
  },
  networks: {
    sepolia: {
      url: SEPOLIA_RPC_URL,
      accounts,
    },
    mainnet: {
      url: MAINNET_RPC_URL || "",
      accounts,
    },
  },
  etherscan: {
    apiKey: ETHERSCAN_API_KEY || "",
  },
};
