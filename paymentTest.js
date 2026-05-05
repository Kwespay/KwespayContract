const hre = require("hardhat");
const { ethers } = hre;

async function main() {
  const network = hre.network.name;
  const [deployer, vendor, customer] = await ethers.getSigners();

  console.log(`Network: ${network}`);
  console.log(`Deployer: ${deployer.address}`);
  console.log(`Vendor:   ${vendor.address}`);
  console.log(`Customer: ${customer.address}`);

  const Payment = await ethers.getContractFactory("Payment");
  const payment = await Payment.deploy();
  await payment.waitForDeployment();
  const paymentAddress = await payment.getAddress();
  console.log(`\nPayment deployed: ${paymentAddress}`);

  const MockUSDT = await ethers.getContractFactory("MockUSDT");
  const usdt = await MockUSDT.deploy("Mock USDT", "USDT", 6, 1_000_000);
  await usdt.waitForDeployment();
  const usdtAddress = await usdt.getAddress();
  console.log(`MockUSDT deployed: ${usdtAddress}`);

  await (await payment.setSupportedToken(usdtAddress, true)).wait();
  await (
    await payment.registerVendorByOwner(
      "vendor-1",
      vendor.address,
      "Test Vendor"
    )
  ).wait();

  const mintAmount = ethers.parseUnits("1000", 6);
  await (await usdt.mint(customer.address, mintAmount)).wait();
  await (
    await usdt.connect(customer).approve(paymentAddress, mintAmount)
  ).wait();

  const paymentId = ethers.hexlify(ethers.randomBytes(32));
  const amount = ethers.parseUnits("100", 6);
  const deadline = Math.floor(Date.now() / 1000) + 3600; // 1 hour
  const chainId = (await ethers.provider.getNetwork()).chainId;

  const hash = ethers.solidityPackedKeccak256(
    [
      "bytes32",
      "string",
      "address",
      "uint256",
      "uint256",
      "uint256",
      "address",
    ],
    [
      paymentId,
      "vendor-1",
      usdtAddress,
      amount,
      deadline,
      chainId,
      paymentAddress,
    ]
  );

  // deployer == owner() == the expected signer
  const backendSignature = await deployer.signMessage(ethers.getBytes(hash));

  const vendorBefore = await usdt.balanceOf(vendor.address);
  const feeBefore = await usdt.balanceOf(deployer.address);

  await (
    await payment.connect(customer).createPayment({
      paymentId,
      vendorId: "vendor-1",
      token: usdtAddress,
      amount,
      deadline,
      backendSignature,
    })
  ).wait();

  const vendorAfter = await usdt.balanceOf(vendor.address);
  const feeAfter = await usdt.balanceOf(deployer.address);

  console.log(`\nPayment amount:   ${ethers.formatUnits(amount, 6)} USDT`);
  console.log(
    `Vendor received:  ${ethers.formatUnits(
      vendorAfter - vendorBefore,
      6
    )} USDT`
  );
  console.log(
    `Platform fee:     ${ethers.formatUnits(feeAfter - feeBefore, 6)} USDT`
  );
  console.log("\nAll tests passed ✓");
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
