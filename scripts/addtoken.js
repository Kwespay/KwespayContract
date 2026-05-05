const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  const network = hre.network.name;
  const [deployer] = await hre.ethers.getSigners();

  const deploymentFile = path.join(__dirname, `../deployments/${network}.json`);
  if (!fs.existsSync(deploymentFile)) {
    throw new Error(`No deployment found for network: ${network}`);
  }

  const deployment = JSON.parse(fs.readFileSync(deploymentFile, "utf8"));
  const contractAddress = deployment.contractAddress;

  const tokenAddress = process.env.TOKEN_ADDRESS;
  const supported = process.env.SUPPORTED !== "false";

  if (!tokenAddress) {
    throw new Error("TOKEN_ADDRESS env variable is required");
  }

  console.log(`Network: ${network}`);
  console.log(`Contract: ${contractAddress}`);
  console.log(`Token: ${tokenAddress}`);
  console.log(`Supported: ${supported}`);

  const Payment = await hre.ethers.getContractFactory("Payment");
  const contract = Payment.attach(contractAddress);

  const tx = await contract.setSupportedToken(tokenAddress, supported);
  await tx.wait();

  console.log(`Token ${supported ? "added" : "removed"} successfully`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
