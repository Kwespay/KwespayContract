const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  const network = hre.network.name;
  const signers = await hre.ethers.getSigners();

  if (!signers || signers.length === 0) {
    throw new Error(
      "No signers found. Make sure PRIVATE_KEY is set in your .env file."
    );
  }

  const deployer = signers[0];

  console.log(`Network: ${network}`);
  console.log(`Deployer: ${deployer.address}`);
  console.log(
    `Balance: ${hre.ethers.formatEther(
      await hre.ethers.provider.getBalance(deployer.address)
    )} ETH\n`
  );

  const Payment = await hre.ethers.getContractFactory("Payment");
  const contract = await Payment.deploy();
  await contract.waitForDeployment();
  const contractAddress = await contract.getAddress();

  console.log(`Payment deployed to: ${contractAddress}`);

  const tokenConfigs = getTokenConfigs(network);
  const deployedTokens = [];

  if (isTestnet(network) && needsMockTokens(network)) {
    console.log("Deploying MockUSDT...");
    const MockUSDT = await hre.ethers.getContractFactory("MockUSDT");
    const mockUsdt = await MockUSDT.deploy("Mock USDT", "USDT", 6, 1_000_000);
    await mockUsdt.waitForDeployment();
    const mockUsdtAddress = await mockUsdt.getAddress();

    console.log(`MockUSDT deployed to: ${mockUsdtAddress}`);

    const addTx = await contract.setSupportedToken(mockUsdtAddress, true);
    await addTx.wait();

    deployedTokens.push({
      name: "Mock USDT",
      address: mockUsdtAddress,
      deployed: true,
    });
  }

  if (tokenConfigs.length > 0) {
    console.log("Configuring supported tokens...");
    for (const token of tokenConfigs) {
      console.log(`  Adding ${token.name}: ${token.address}`);
      const tx = await contract.setSupportedToken(token.address, true);
      await tx.wait();
      deployedTokens.push({ ...token, deployed: false });
    }
  }

  const deploymentsDir = path.join(__dirname, "../deployments");
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir, { recursive: true });
  }

  const deploymentInfo = {
    network,
    contractAddress,
    deployer: deployer.address,
    deployedAt: new Date().toISOString(),
    blockNumber: await hre.ethers.provider.getBlockNumber(),
    supportedTokens: deployedTokens,
  };

  const deploymentFile = path.join(deploymentsDir, `${network}.json`);
  fs.writeFileSync(deploymentFile, JSON.stringify(deploymentInfo, null, 2));
  console.log(`Deployment info saved to: ${deploymentFile}`);

  const artifactPath = path.join(
    __dirname,
    "../artifacts/contracts/payment.sol/Payment.json"
  );
  const artifact = JSON.parse(fs.readFileSync(artifactPath, "utf8"));
  const abiFile = path.join(deploymentsDir, "PaymentABI.json");
  fs.writeFileSync(abiFile, JSON.stringify({ abi: artifact.abi }, null, 2));
  console.log(`ABI saved to: ${abiFile}`);

  if (network !== "localhost" && network !== "hardhat") {
    console.log("Waiting for block confirmations...");
    await contract.deploymentTransaction().wait(6);

    console.log("Verifying contract...");
    try {
      await hre.run("verify:verify", {
        address: contractAddress,
        constructorArguments: [],
      });
      console.log("Contract verified");
    } catch (error) {
      console.log("Verification failed:", error.message);
    }
  }

  console.log("\n" + "=".repeat(60));
  console.log("DEPLOYMENT COMPLETE");
  console.log("=".repeat(60));
  console.log(`\n${network.toUpperCase()}_CONTRACT_ADDRESS=${contractAddress}`);
}

function isTestnet(network) {
  return [
    "sepolia",
    "baseSepolia",
    "polygonAmoy",
    "liskTestnet",
    "mezoTestnet",
    "localhost",
    "hardhat",
  ].includes(network);
}

function needsMockTokens(network) {
  return ["mezoTestnet", "localhost", "hardhat"].includes(network);
}

function getTokenConfigs(network) {
  const configs = {
    mainnet: [
      { name: "USDT", address: "0xdAC17F958D2ee523a2206206994597C13D831ec7" },
      { name: "USDC", address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48" },
    ],
    sepolia: [
      {
        name: "Mock USDT",
        address: "0x261322E2378467dd1cF5ac60A66817223db68fA3",
      },
    ],
    base: [
      { name: "USDC", address: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913" },
    ],
    baseSepolia: [
      {
        name: "Mock USDC",
        address: "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
      },
    ],
    polygon: [
      { name: "USDT", address: "0xc2132D05D31c914a87C6611C10748AEb04B58e8F" },
    ],
    polygonAmoy: [
      {
        name: "Mock USDC",
        address: "0x8B0180f2101c8260d49339abfEe87927412494B4",
      },
    ],
    lisk: [],
    liskTestnet: [
      { name: "LSK", address: "0x8a21CF9Ba08Ae709D64Cb25AfAA951183EC9FF6D" },
    ],
    mezoTestnet: [],
    localhost: [],
    hardhat: [],
  };

  return configs[network] || [];
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\nError:", error.message);
    process.exit(1);
  });
