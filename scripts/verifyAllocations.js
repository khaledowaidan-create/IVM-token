require("dotenv").config();
const hre = require("hardhat");

function requireEnv(name) {
  const value = process.env[name];
  if (!value || !/^0x[a-fA-F0-9]{40}$/.test(value)) {
    throw new Error(`Set a valid ${name} (0x-prefixed address).`);
  }
  return value;
}

async function verifyTranche(label, address) {
  console.log(`\nVerifying ${label} vesting at ${address}...`);
  const vesting = await hre.ethers.getContractAt("TrancheVestingWallet", address);
  const args = [
    await vesting.token(),
    await vesting.beneficiary(),
    (await vesting.start()).toString(),
    (await vesting.period()).toString(),
    (await vesting.totalTranches()).toString(),
    await vesting.owner(),
  ];

  await runVerify(address, "contracts/IVMToken.sol:TrancheVestingWallet", args);
}

async function verifyLoyalty(address) {
  console.log(`\nVerifying LoyaltyVault at ${address}...`);
  const vault = await hre.ethers.getContractAt("LoyaltyVault", address);
  const args = [
    await vault.token(),
    (await vault.releaseTime()).toString(),
    await vault.admin(),
    await vault.owner(),
  ];

  await runVerify(address, "contracts/IVMToken.sol:LoyaltyVault", args);
}

async function runVerify(address, contractPath, constructorArguments) {
  try {
    await hre.run("verify:verify", {
      address,
      contract: contractPath,
      constructorArguments,
    });
    console.log("✔ Verification submitted.");
  } catch (error) {
    if (error.message && error.message.includes("Already Verified")) {
      console.log("ℹ Contract already verified on Etherscan.");
      return;
    }
    console.error("Verification failed:", error);
    throw error;
  }
}

async function getAllocationAddresses(ivmAddress) {
  const ivm = await hre.ethers.getContractAt("IVMToken", ivmAddress);
  try {
    const initialized = await ivm.allocationsInitialized();
    if (!initialized) {
      throw new Error("Allocations are not initialized on this deployment.");
    }
    return {
      marketing: await ivm.marketingVesting(),
      development: await ivm.devTechVesting(),
      team: await ivm.teamVesting(),
      reserve: await ivm.reserveVesting(),
      loyalty: await ivm.loyaltyVault(),
    };
  } catch (error) {
    if (error.code !== "BAD_DATA") throw error;
    console.warn(
      "allocationsInitialized() call failed, falling back to AllocationsInitialized event lookup."
    );
    const eventFragment =
      "event AllocationsInitialized(address indexed community,address indexed marketingBeneficiary,address indexed devTechBeneficiary,address marketingVesting,address devTechVesting,address teamVesting,address reserveVesting,address loyaltyVault)";
    const iface = new hre.ethers.Interface([eventFragment]);
    const topic = hre.ethers.id(
      "AllocationsInitialized(address,address,address,address,address,address,address,address)"
    );
    const log = await findAllocationsLog(ivmAddress, topic);
    if (!log) {
      throw new Error("AllocationsInitialized event not found; cannot resolve vesting addresses.");
    }
    const parsed = iface.parseLog(log);
    return {
      marketing: parsed.args.marketingVesting,
      development: parsed.args.devTechVesting,
      team: parsed.args.teamVesting,
      reserve: parsed.args.reserveVesting,
      loyalty: parsed.args.loyaltyVault,
    };
  }
}

async function findAllocationsLog(address, topic) {
  const provider = hre.ethers.provider;
  const latest = await provider.getBlockNumber();
  const window = 10;
  const maxLookback = 200_000;

  for (let to = latest; to >= 0 && latest - to <= maxLookback; to -= window) {
    const from = Math.max(to - window + 1, 0);
    try {
      const logs = await provider.getLogs({
        address,
        topics: [topic],
        fromBlock: from,
        toBlock: to,
      });
      if (logs.length) {
        return logs[logs.length - 1];
      }
    } catch (providerError) {
      if (
        providerError instanceof Error &&
        providerError.message.includes("eth_getLogs")
      ) {
        throw providerError;
      }
      throw providerError;
    }
  }
  return null;
}

async function main() {
  const ivmAddress = requireEnv("IVM_TOKEN_ADDRESS");
  const addresses = await getAllocationAddresses(ivmAddress);

  await verifyTranche("Marketing", addresses.marketing);
  await verifyTranche("Development & Tech", addresses.development);
  await verifyTranche("Team", addresses.team);
  await verifyTranche("Reserve", addresses.reserve);
  await verifyLoyalty(addresses.loyalty);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
