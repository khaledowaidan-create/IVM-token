const hre = require("hardhat");

async function main() {
  const provider = hre.ethers.provider;
  const rawKey = process.env.PRIVATE_KEY || "";
  const deployer = new hre.ethers.Wallet(
    rawKey.startsWith("0x") ? rawKey : `0x${rawKey}`,
    provider
  );
  console.log("Deployer:", await deployer.getAddress());

  const {
    COMMUNITY_WALLET,
    MARKETING_WALLET,
    DEVELOPMENT_WALLET,
    TEAM_WALLET,
    RESERVE_WALLET,
    LOYALTY_WALLET,
  } = process.env;

  const allocationAddresses = {
    COMMUNITY_WALLET,
    MARKETING_WALLET,
    DEVELOPMENT_WALLET,
    TEAM_WALLET,
    RESERVE_WALLET,
    LOYALTY_WALLET,
  };

  for (const [label, addr] of Object.entries(allocationAddresses)) {
    if (!addr || !/^0x[a-fA-F0-9]{40}$/.test(addr)) {
      throw new Error(`Missing or invalid ${label} in .env (expected 0x-prefixed 40 hex chars)`);
    }
  }

  // 1) نشر العقد
  const ivmFactory = await hre.ethers.getContractFactory("IVMToken", deployer);
  const ivm = await ivmFactory.deploy();
  await ivm.waitForDeployment();
  const addr = await ivm.getAddress();
  console.log("IVM deployed at:", addr);

  // تأكيد عدد من الكتل قبل المتابعة خصوصًا على mainnet
  const deploymentTx = ivm.deploymentTransaction();
  const confirmationsNeeded = hre.network.name === "mainnet" ? 5 : 2;
  if (deploymentTx) {
    console.log(`Waiting for ${confirmationsNeeded} confirmations...`);
    await deploymentTx.wait(confirmationsNeeded);
  }

  // 2) تهيئة التوزيع (مرة واحدة فقط)
  const tx1 = await ivm.setupAllocations(
    COMMUNITY_WALLET,
    MARKETING_WALLET,
    DEVELOPMENT_WALLET,
    TEAM_WALLET,
    RESERVE_WALLET,
    LOYALTY_WALLET
  );
  await tx1.wait();
  console.log("Allocations initialized.");

  // 3) (اختياري الآن/لاحقًا) تسجيل زوج السيولة لتفعيل حرق الشراء 0.08%
  // بعد ما تنشئ ال-Pair في Uniswap، ضع عنوانه هنا:
  // const tx2 = await ivm.setMarketPair("0xYourPairAddress");
  // await tx2.wait();
  // console.log("marketPair set.");

  // 4) (اختياري) تأكيد نسبة الحرق عند الشراء 0.08% (افتراضيًا مفعلة وبـ 8bps)
  // await (await ivm.setBuyBurn(true, 8)).wait();

  // 5) (اختياري) إبقاء الحرق العام معطّل في البداية
  // await (await ivm.setAutoBurn(false, 0)).wait();

  console.log("Done.");

  await verifyOnEtherscan(addr);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});

async function verifyOnEtherscan(address) {
  const { ETHERSCAN_API_KEY } = process.env;
  if (!ETHERSCAN_API_KEY) {
    console.log("ETHERSCAN_API_KEY missing; skipping automatic verification.");
    return;
  }
  if (["hardhat", "localhost"].includes(hre.network.name)) {
    console.log(`Skipping verification on ${hre.network.name} network.`);
    return;
  }

  console.log(`Verifying contract ${address} on ${hre.network.name}...`);
  try {
    await hre.run("verify:verify", {
      address,
      constructorArguments: [],
    });
    console.log("Verification complete.");
  } catch (error) {
    if (error.message && error.message.includes("Already Verified")) {
      console.log("Contract already verified on Etherscan.");
      return;
    }
    console.error("Verification failed:", error);
  }
}
