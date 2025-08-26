const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying with account:", deployer.address);

  // Deploy tokens
  const DAppToken = await hre.ethers.getContractFactory("DAppToken");
  const dapp = await DAppToken.deploy(deployer.address);
  await dapp.waitForDeployment();
  console.log("DAppToken:", await dapp.getAddress());

  const LPToken = await hre.ethers.getContractFactory("LPToken");
  const lpt = await LPToken.deploy(deployer.address);
  await lpt.waitForDeployment();
  console.log("LPToken:", await lpt.getAddress());

  // Deploy farm
  const TokenFarm = await hre.ethers.getContractFactory("TokenFarm");
  const farm = await TokenFarm.deploy(await dapp.getAddress(), await lpt.getAddress());
  await farm.waitForDeployment();
  console.log("TokenFarm:", await farm.getAddress());

  // Transferir propiedad del DAPP a la Farm
  const txOwn = await dapp.transferOwnership(await farm.getAddress());
  await txOwn.wait();
  console.log("DAppToken ownership transferred to Farm");

  console.log("Deploy completo en Sepolia");
  console.log("Direcciones de los contratos:");
  console.log(" DAppToken:", await dapp.getAddress());
  console.log(" LPToken  :", await lpt.getAddress());
  console.log(" TokenFarm:", await farm.getAddress());
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
