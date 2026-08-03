const Settlement = artifacts.require("Settlement");
const Token1 = artifacts.require("Token1");
const Token2 = artifacts.require("Token2");
const Token3 = artifacts.require("Token3");

module.exports = function(deployer, network, accounts) {
  if(network === "development"){
    console.error("USING DEVELOPMENT")
    deployer.deploy(Settlement, {from: accounts[0]});
    deployer.deploy(Token1, {from: accounts[0]});
    deployer.deploy(Token2, {from: accounts[0]});
    deployer.deploy(Token3, {from: accounts[0]});
  }
  if(network === "testnet") {
    console.error("USING TESTNET")
    deployer.deploy(Settlement, {from: accounts[0]}).then(async (settlementInstance) => {
      await settlementInstance.setExecutor("0x4363192678DC135534404464BDD27E194A857F5a", {from: accounts[0]});
      //sets custodianAddresses allowed
      await settlementInstance.setAddressAllowable("0xff67fB8328143daA1A8EDe353Aa76cc560f38960", {from: accounts[0]});
      await settlementInstance.setAddressAllowable("0x9119EDfFE1F6Dd7B08981fD001af9A5D6CF0aCec", {from: accounts[0]});
      await settlementInstance.setAddressAllowable("0xc64aD624C642b7e4EC1B49e5B34c82D7BcF923eE", {from: accounts[0]});
      await settlementInstance.setAddressAllowable("0x9434Fc37884d3d6f32aF4D2D76024085eCb7cCB3", {from: accounts[0]});
      await settlementInstance.setAddressAllowable("0x9480FfCb590d44CA340B93b785bb3CF22c408453", {from: accounts[0]});

      //sets tokens allowed
      await settlementInstance.setTokenAllowable("0xf1240A08B80728cE3D70440bE8483b53ca19247f", {from: accounts[0]});
      await settlementInstance.setTokenAllowable("0xC3d470251498FF8cf70bF33879064802C908C774", {from: accounts[0]});
      await settlementInstance.setTokenAllowable("0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6", {from: accounts[0]});
      await settlementInstance.setTokenAllowable("0x326C977E6efc84E512bB9C30f76E30c160eD06FB", {from: accounts[0]});
    });
  }
  if(network === "mainnet"){
    console.error("USING MAINNET")
    deployer.deploy(Settlement, {from: accounts[0]});
  }
};