const { BN } = require("bn.js");
const { eventEmitted } = require("truffle-assertions");
const truffleAssert = require("truffle-assertions");
const Web3 = require('web3');
const web3 = new Web3(Web3.givenProvider || "ws://localhost:8545");

const Settlement = artifacts.require("Settlement");
const Token1 = artifacts.require("Token1");
const Token2 = artifacts.require("Token2");
const Token3 = artifacts.require("Token3");

const ETHEREUM_BLOCK_GAS_LIMIT = 30000000;

let custodianMocks;

var settlementInstance;
var token1Instance;
var token2Instance;
var token3Instance;

const arrayEquals = (a, b) =>
  a.length === b.length &&
  a.every((v, i) => v === b[i]);

contract('Settlement', (accounts) => {
  before(async () => {
    custodianMocks = 
    {
      EXCHANGE: accounts[0],
      JPM: accounts[1],
      BOA: accounts[2],
      BANK: accounts[3],
      EXECUTOR: accounts[4], 
      ADMIN: accounts[5]
    };
  });
  //Recreates and redeploys all contracts to start from a clean state
  beforeEach(async () => {
    settlementInstance = await Settlement.new({from: custodianMocks.ADMIN});
    await settlementInstance.setExecutor(custodianMocks.EXECUTOR, {from: custodianMocks.ADMIN});
    token1Instance = await Token1.new({from: custodianMocks.EXCHANGE});
    token2Instance = await Token2.new({from: custodianMocks.EXCHANGE});
    token3Instance = await Token3.new({from: custodianMocks.EXCHANGE});
  });
  async function setCustodiansAndTokensAsAllowable(custodianAddresses, tokenAddresses) {
    for (address of custodianAddresses) {
      await settlementInstance.setAddressAllowable(address, {from: custodianMocks.ADMIN});
    }
    for (address of tokenAddresses) {
      await settlementInstance.setTokenAllowable(address, {from: custodianMocks.ADMIN});
    }
  };
  async function approveAndDepositTokens(tokensInstances, amounts, custodianAddress){
    assert(tokensInstances.length === amounts.length);
    for (index = 0; index < tokensInstances.length; index++) {      
      await tokensInstances[index].transfer(custodianAddress, amounts[index], {from: custodianMocks.EXCHANGE});
      await tokensInstances[index].approve(settlementInstance.address, amounts[index], {from: custodianAddress});
      await settlementInstance.deposit(tokensInstances[index].address, amounts[index], {from: custodianAddress});
    }
  }
  it('should deploy at a not null address', async () => {
    console.log(settlementInstance.address);
    assert(settlementInstance.address !== '');
  });
  it('should cost less than block limit gas', async () => {   
        const creationTx = await Settlement.new({from: custodianMocks.ADMIN});
        let receipt  = await web3.eth.getTransactionReceipt(creationTx.transactionHash);
        assert(receipt.gasUsed < ETHEREUM_BLOCK_GAS_LIMIT);
  });
  describe('deposit', () => {
    describe('deposit token', () => {
      it('has correct balance for depositor and zero for non depositor', async () => {
        await setCustodiansAndTokensAsAllowable([custodianMocks.EXCHANGE], [token1Instance.address]);
        await approveAndDepositTokens([token1Instance], [1000], custodianMocks.EXCHANGE);

        var contractBalanceOfToken1 = await token1Instance.balanceOf.call(settlementInstance.address);
        assert(contractBalanceOfToken1.toString() === "1000");
        const resultFromDepositor = await settlementInstance.getBalanceOfToken.call(custodianMocks.EXCHANGE, token1Instance.address);
        assert(resultFromDepositor.toString() === "1000");
        const resultFromOther = await settlementInstance.getBalanceOfToken.call(custodianMocks.JPM, token1Instance.address);
        assert(resultFromOther.toString() === "0");
      });
      it('throws error when deposited token does not have allowance', async () => {
        truffleAssert.fails(settlementInstance.deposit(token1Instance.address, 1000, {from: custodianMocks.EXCHANGE}));
      });
      it('throws error when depositor is not registered', async () => {
        await setCustodiansAndTokensAsAllowable([], [token1Instance.address]);
        await settlementInstance.setTokenAllowable(token1Instance.address, {from: custodianMocks.ADMIN});
        await token1Instance.approve(settlementInstance.address, 1000, {from: custodianMocks.EXCHANGE});
        truffleAssert.fails(settlementInstance.deposit(token1Instance.address, 1000, {from: custodianMocks.EXCHANGE}));
      });
      it('throws error when token deposited is not registered', async () => {
        await setCustodiansAndTokensAsAllowable([custodianMocks.EXCHANGE], []);
        await token1Instance.approve(settlementInstance.address, 1000, {from: custodianMocks.EXCHANGE});
        truffleAssert.fails(settlementInstance.deposit(token1Instance.address, 1000, {from: custodianMocks.EXCHANGE}));
      });
    });  
  });
  describe('createPendingSettlement', () => {
    it('creates Pending Settlement when executed by executor, tokens are registered along with creditor/debitor pair', async () => {
      await setCustodiansAndTokensAsAllowable([custodianMocks.BOA, custodianMocks.JPM], [token1Instance.address, token2Instance.address]);
      await truffleAssert.passes(settlementInstance.createPendingSettlement(0, custodianMocks.BOA, custodianMocks.JPM, [token1Instance.address, token2Instance.address], 
        [100, 1000], {from: custodianMocks.EXECUTOR}));
      const events = await settlementInstance.getPastEvents('PendingSettlement');
      assert(events.length === 1);
    });
    it('fails when not executed by executor', async () => {
      await setCustodiansAndTokensAsAllowable([custodianMocks.BOA, custodianMocks.JPM], [token1Instance.address, token2Instance.address]);

      await truffleAssert.fails(settlementInstance.createPendingSettlement(0, custodianMocks.BOA, custodianMocks.JPM, [token1Instance.address, token2Instance.address], 
        [100, 1000], {from: custodianMocks.ADMIN}));
      const events = await settlementInstance.getPastEvents('PendingSettlement');
      assert(events.length === 0);      
    });
    it('fails when addresses are different than amounts', async () => {
      await setCustodiansAndTokensAsAllowable([custodianMocks.BOA, custodianMocks.JPM], [token1Instance.address, token2Instance.address]);

      await truffleAssert.fails(settlementInstance.createPendingSettlement(0, custodianMocks.BOA, custodianMocks.JPM, [token1Instance.address, token2Instance.address, token3Instance.address], 
        [100, 1000], {from: custodianMocks.EXECUTOR}));      
    });

    it('fails when debitor or creditor is not registered', async () => {
      await setCustodiansAndTokensAsAllowable([custodianMocks.JPM], [token1Instance.address, token2Instance.address]);
      
      await truffleAssert.fails(settlementInstance.createPendingSettlement(0, custodianMocks.BOA, custodianMocks.JPM, [token1Instance.address, token2Instance.address, token3Instance.address], 
        [100, 1000], {from: custodianMocks.EXECUTOR}));
      await truffleAssert.fails(settlementInstance.createPendingSettlement(1, custodianMocks.JPM, custodianMocks.BOA, [token1Instance.address, token2Instance.address, token3Instance.address], 
        [100, 1000], {from: custodianMocks.EXECUTOR}));       
    });
    it('fails when token is not registered', async () => {
      await setCustodiansAndTokensAsAllowable([custodianMocks.BOA, custodianMocks.JPM], [token1Instance.address]);
      
      await truffleAssert.fails(settlementInstance.createPendingSettlement(0, custodianMocks.JPM, custodianMocks.BOA, [token1Instance.address, token2Instance.address, token3Instance.address], 
        [100, 1000], {from: custodianMocks.EXECUTOR}));       
    });
    it('fails when trying to create settlement with a previously created settlementId', async () => {
      await setCustodiansAndTokensAsAllowable([custodianMocks.BOA, custodianMocks.JPM], [token1Instance.address, token2Instance.address]);
      
      await truffleAssert.passes(settlementInstance.createPendingSettlement(0, custodianMocks.JPM, custodianMocks.BOA, [token1Instance.address, token2Instance.address], 
        [100, 1000], {from: custodianMocks.EXECUTOR}));
      await truffleAssert.fails(settlementInstance.createPendingSettlement(0, custodianMocks.JPM, custodianMocks.BOA, [token1Instance.address, token2Instance.address], 
        [100, 1000], {from: custodianMocks.EXECUTOR}));        
    });
    it('fails when contract is paused', async () => {
      await setCustodiansAndTokensAsAllowable([custodianMocks.BOA, custodianMocks.JPM], [token1Instance.address, token2Instance.address]);
      
      await settlementInstance.pause({from: custodianMocks.ADMIN});
      await truffleAssert.fails(settlementInstance.createPendingSettlement(0, custodianMocks.JPM, custodianMocks.BOA, [token1Instance.address, token2Instance.address], 
        [100, 1000], {from: custodianMocks.EXECUTOR}));       
    });
  });
  describe('executeSettlement', () => {
    describe('when funds are available', () => {
      it('executes settlement', async () => {
        //set custodians and tokens as allowable
        await setCustodiansAndTokensAsAllowable([custodianMocks.BOA, custodianMocks.JPM], [token1Instance.address, token2Instance.address]);
        //Deposits tokens to custodian
        await approveAndDepositTokens([token1Instance, token2Instance], [600, 300], custodianMocks.JPM);

        //Creates Pending Settlement from JPM to BOA
        await truffleAssert.passes(await settlementInstance.createPendingSettlement(0, custodianMocks.JPM, custodianMocks.BOA, [token1Instance.address, token2Instance.address], 
          [600, 300], {from: custodianMocks.EXECUTOR}));

        await settlementInstance.authorizeSettlement(0, {from: custodianMocks.JPM});

        //Executes settlement
        await truffleAssert.passes(settlementInstance.executeSettlement([0], {from: custodianMocks.EXECUTOR}));

        //gets balances after settlement
        const JPMBalanceOfToken1 = await settlementInstance.getBalanceOfToken.call(custodianMocks.JPM, token1Instance.address);
        const JPMBalanceOfToken2 = await settlementInstance.getBalanceOfToken.call(custodianMocks.JPM, token2Instance.address);
        const BOABalanceOfToken1 = await settlementInstance.getBalanceOfToken.call(custodianMocks.BOA, token1Instance.address);
        const BOABalanceOfToken2 = await settlementInstance.getBalanceOfToken.call(custodianMocks.BOA, token2Instance.address);

        assert(JPMBalanceOfToken1.toString() === "0");
        assert(JPMBalanceOfToken2.toString() === "0");
        assert(BOABalanceOfToken1.toString() === "600");
        assert(BOABalanceOfToken2.toString() === "300");

        const events = await settlementInstance.getPastEvents('ExecutedSettlement');
        assert(events.length === 1);
      });
      it('creates two settlements of one token, executes 1st and fails 2nd due to lack of funds', async () => {
        await setCustodiansAndTokensAsAllowable([custodianMocks.BOA, custodianMocks.JPM], [token1Instance.address]);
        //Deposits tokens to custodian approves tokens and deposit funds
        await approveAndDepositTokens([token1Instance], [500], custodianMocks.JPM);
        //Creates Pending Settlement from JPM to BOA
        await truffleAssert.passes(settlementInstance.createPendingSettlement(0, custodianMocks.JPM, custodianMocks.BOA, [token1Instance.address], 
          [350], {from: custodianMocks.EXECUTOR}));
        
        await truffleAssert.passes(settlementInstance.createPendingSettlement(1, custodianMocks.JPM, custodianMocks.BOA, [token1Instance.address], 
          [200], {from: custodianMocks.EXECUTOR}));

        //Executes settlement
        await truffleAssert.passes(settlementInstance.authorizeSettlement(0, {from: custodianMocks.JPM}));
        await truffleAssert.fails(settlementInstance.authorizeSettlement(1, {from: custodianMocks.JPM}));
        await truffleAssert.passes(settlementInstance.executeSettlement([0], {from: custodianMocks.EXECUTOR}));

        //gets balances after settlement
        const JPMBalanceOfToken1 = await settlementInstance.getBalanceOfToken.call(custodianMocks.JPM, token1Instance.address);
        const BOABalanceOfToken1 = await settlementInstance.getBalanceOfToken.call(custodianMocks.BOA, token1Instance.address);

        assert(JPMBalanceOfToken1.toString() === "150");
        assert(BOABalanceOfToken1.toString() === "350");

        const events = await settlementInstance.getPastEvents('ExecutedSettlement');
        assert(events.length === 1);
        await truffleAssert.fails(settlementInstance.executeSettlement([1], {from: custodianMocks.EXECUTOR}));
        
      });
      it('fails when executing same settlement twice', async () => {
        await setCustodiansAndTokensAsAllowable([custodianMocks.BOA, custodianMocks.JPM], [token1Instance.address]);
        //Deposits tokens to custodian approves tokens and deposit funds
        await approveAndDepositTokens([token1Instance], [700], custodianMocks.JPM);
        //Creates Pending Settlement from JPM to BOA
        await truffleAssert.passes(settlementInstance.createPendingSettlement(0, custodianMocks.JPM, custodianMocks.BOA, [token1Instance.address], 
          [350], {from: custodianMocks.EXECUTOR}));
        
        await truffleAssert.passes(settlementInstance.createPendingSettlement(1, custodianMocks.JPM, custodianMocks.BOA, [token1Instance.address], 
          [200], {from: custodianMocks.EXECUTOR}));        

        //Executes settlement
        await settlementInstance.authorizeSettlement(0, {from: custodianMocks.JPM});
        await truffleAssert.passes(settlementInstance.executeSettlement([0], {from: custodianMocks.EXECUTOR}));
        const events = await settlementInstance.getPastEvents('ExecutedSettlement');
        assert(events.length === 1)
        await truffleAssert.fails(settlementInstance.executeSettlement([0], {from: custodianMocks.EXECUTOR}));
      });
      it('fails when contract is paused', async () => {
        await setCustodiansAndTokensAsAllowable([custodianMocks.BOA, custodianMocks.JPM], [token1Instance.address]);
        //Deposits tokens to custodian approves tokens and deposit funds
        await approveAndDepositTokens([token1Instance], [500], custodianMocks.JPM);
        //Creates Pending Settlement from JPM to BOA
        await truffleAssert.passes(settlementInstance.createPendingSettlement(0, custodianMocks.JPM, custodianMocks.BOA, [token1Instance.address], 
          [350], {from: custodianMocks.EXECUTOR}));
        
        await truffleAssert.passes(settlementInstance.createPendingSettlement(1, custodianMocks.JPM, custodianMocks.BOA, [token1Instance.address], 
          [200], {from: custodianMocks.EXECUTOR}));

        await settlementInstance.pause({from: custodianMocks.ADMIN});

        //Executes settlement
        await settlementInstance.authorizeSettlement(0, {from: custodianMocks.JPM});
        await truffleAssert.fails(settlementInstance.executeSettlement([0], {from: custodianMocks.EXECUTOR}));
      });
      it('fails when settlement is not authorized', async () => {
        //set custodians and tokens as allowable
        await setCustodiansAndTokensAsAllowable([custodianMocks.BOA, custodianMocks.JPM], [token1Instance.address, token2Instance.address]);
        //Deposits tokens to custodian approves tokens and deposit funds
        await approveAndDepositTokens([token1Instance], [600], custodianMocks.JPM);
        //Creates Pending Settlement from JPM to BOA
        await truffleAssert.passes(await settlementInstance.createPendingSettlement(0, custodianMocks.JPM, custodianMocks.BOA, [token1Instance.address], 
          [300], {from: custodianMocks.EXECUTOR}));
        //Executes settlement
        await truffleAssert.fails(settlementInstance.executeSettlement([0], {from: custodianMocks.EXECUTOR}));
      });
    });
  });
  describe('authorizeSettlement', () => {
    describe('when executed by debtor', () => {
      it('sets Settlement as authorized', async () => {
        await setCustodiansAndTokensAsAllowable([custodianMocks.BOA, custodianMocks.JPM], [token1Instance.address, token2Instance.address]);
        //Deposits tokens to custodian approves tokens and deposit funds
        await approveAndDepositTokens([token1Instance, token2Instance], [600, 300], custodianMocks.JPM);
        //Creates Pending Settlement from JPM to BOA
        await truffleAssert.passes(await settlementInstance.createPendingSettlement(0, custodianMocks.JPM, custodianMocks.BOA, [token1Instance.address, token2Instance.address], 
          [600, 300], {from: custodianMocks.EXECUTOR}));
        var beforeApproval = await settlementInstance.getSettlementData.call(0);
        var lockedBalanceBeforeAuth = await settlementInstance.getLockedBalanceOfToken.call(custodianMocks.JPM, token1Instance.address);
        var balanceBeforeAuth = await settlementInstance.getBalanceOfToken.call(custodianMocks.JPM, token1Instance.address);
        assert(beforeApproval[4] == false); //authorization boolean
        assert(lockedBalanceBeforeAuth == "0");
        assert(balanceBeforeAuth == "600");
        var result = await settlementInstance.authorizeSettlement(0, {from: custodianMocks.JPM});
        var lockedBalanceAfterAuth = await settlementInstance.getLockedBalanceOfToken.call(custodianMocks.JPM, token1Instance.address);
        var balanceAfterAuth = await settlementInstance.getBalanceOfToken.call(custodianMocks.JPM, token1Instance.address);
        var afterApproval = await settlementInstance.getSettlementData.call(0);
        assert(lockedBalanceAfterAuth == "600");
        assert(balanceAfterAuth == "0");
        assert(afterApproval[4] == true); //authorization boolean
        truffleAssert.eventEmitted(result, 'CustodianSignature')
      });
      it('fails to set Settlement as authorized due to insufficient funds', async () => {
        await setCustodiansAndTokensAsAllowable([custodianMocks.BOA, custodianMocks.JPM], [token1Instance.address, token2Instance.address]);
        //Deposits tokens to custodian approves tokens and deposit funds
        await approveAndDepositTokens([token1Instance, token2Instance], [600, 200], custodianMocks.JPM);
        //Creates Pending Settlement from JPM to BOA
        await truffleAssert.passes(await settlementInstance.createPendingSettlement(0, custodianMocks.JPM, custodianMocks.BOA, [token1Instance.address, token2Instance.address], 
          [600, 300], {from: custodianMocks.EXECUTOR}));        
        await truffleAssert.fails(settlementInstance.authorizeSettlement(0, {from: custodianMocks.JPM}));
      });
      it('fails to redeem locked funds after authorized', async () => {
        await setCustodiansAndTokensAsAllowable([custodianMocks.BOA, custodianMocks.JPM], [token1Instance.address, token2Instance.address]);
        //Deposits tokens to custodian approves tokens and deposit funds
        await approveAndDepositTokens([token1Instance], [600], custodianMocks.JPM);
        //Creates Pending Settlement from JPM to BOA
        await settlementInstance.createPendingSettlement(0, custodianMocks.JPM, custodianMocks.BOA, [token1Instance.address], 
          [600], {from: custodianMocks.EXECUTOR});
        await truffleAssert.passes(settlementInstance.authorizeSettlement(0, {from: custodianMocks.JPM}));
        var lockedBalance = await settlementInstance.getLockedBalanceOfToken.call(custodianMocks.JPM, token1Instance.address);
        var balance = await settlementInstance.getBalanceOfToken.call(custodianMocks.JPM, token1Instance.address);
        assert(lockedBalance.toString() === "600");
        assert(balance.toString() === "0");
        await truffleAssert.fails(settlementInstance.redeem(token1Instance.address, 600, {from: custodianMocks.JPM}));
      });
    });     
    describe('when executed by any other entity', () => {
      it('fails', async () => {
        await setCustodiansAndTokensAsAllowable([custodianMocks.BOA, custodianMocks.JPM], [token1Instance.address, token2Instance.address]);
        //Deposits tokens to custodian
        await token1Instance.transfer(custodianMocks.JPM, 5000, {from: custodianMocks.EXCHANGE});
        //Creates Pending Settlement from JPM to BOA
        await truffleAssert.passes(await settlementInstance.createPendingSettlement(0, custodianMocks.JPM, custodianMocks.BOA, [token1Instance.address, token2Instance.address], 
          [600, 300], {from: custodianMocks.EXECUTOR}));
        await truffleAssert.fails(settlementInstance.authorizeSettlement(0, {from: custodianMocks.ADMIN}));
        await truffleAssert.fails(settlementInstance.authorizeSettlement(0, {from: custodianMocks.BANK}));
        await truffleAssert.fails(settlementInstance.authorizeSettlement(0, {from: custodianMocks.BOA}));
        var currentState = await settlementInstance.getSettlementData.call(0);
        assert(currentState[4] == false);
      });
    });
  });
  describe('redeem', () => {
    describe('when sufficient amount', () => {
      it('redeems specified amount', async () => {
        await setCustodiansAndTokensAsAllowable([custodianMocks.JPM], [token1Instance.address]);

        //Deposits tokens to custodian approves tokens and deposit funds
        await approveAndDepositTokens([token1Instance], [500], custodianMocks.JPM);
        let result = await settlementInstance.redeem(token1Instance.address, 300, {from: custodianMocks.JPM});

        const JPMBalanceOfToken1 = await token1Instance.balanceOf.call(custodianMocks.JPM);
        const JPMBalanceInContract = await settlementInstance.getBalanceOfToken.call(custodianMocks.JPM, token1Instance.address);

        assert(JPMBalanceOfToken1.toString() === "300");
        assert(JPMBalanceInContract.toString() === "200");
        truffleAssert.eventEmitted(result, 'Redemption')
      });
      it('does not redeem more than what is owed', async () => {
        await setCustodiansAndTokensAsAllowable([custodianMocks.JPM], [token1Instance.address]);

        //Deposits tokens to custodian approves tokens and deposit funds
        await approveAndDepositTokens([token1Instance], [500], custodianMocks.JPM);
        await truffleAssert.fails(settlementInstance.redeem(token1Instance.address, 600, {from: custodianMocks.JPM}));
      });

      it('does not redeem more than what is owed even when contract has the balance', async () => {
        await setCustodiansAndTokensAsAllowable([custodianMocks.JPM, custodianMocks.BOA], [token1Instance.address]);

        await token1Instance.transfer(custodianMocks.JPM, 5000, {from: custodianMocks.EXCHANGE});
        await token1Instance.transfer(custodianMocks.BOA, 7000, {from: custodianMocks.EXCHANGE});
        await token1Instance.approve(settlementInstance.address, 1000, {from: custodianMocks.JPM});
        await token1Instance.approve(settlementInstance.address, 5000, {from: custodianMocks.BOA});
        await settlementInstance.deposit(token1Instance.address, 500, {from: custodianMocks.JPM});
        await settlementInstance.deposit(token1Instance.address, 4500, {from: custodianMocks.BOA});

        await truffleAssert.fails(settlementInstance.redeem(token1Instance.address, 600, {from: custodianMocks.JPM}));
      });
    });
  });
  describe('getSettlementData', () => {
    it('returns the settlement data', async () => {
      await setCustodiansAndTokensAsAllowable([custodianMocks.BOA, custodianMocks.JPM], [token1Instance.address]);
      //Creates Pending Settlement from JPM to BOA
      await truffleAssert.passes(settlementInstance.createPendingSettlement(0, custodianMocks.JPM, custodianMocks.BOA, [token1Instance.address], 
        [350], {from: custodianMocks.EXECUTOR}));
      var result  = await settlementInstance.getSettlementData.call(0);

      assert(result[0] == custodianMocks.JPM);
      assert(result[1] == custodianMocks.BOA);
      assert(arrayEquals(result[2], [token1Instance.address]));
      assert(result[3][0].toString() == '350');
      assert(result[4] == false);
    });
  });
  describe('administrative functions', () => {
    describe('setExecutor', () => {
      it('sets new executor', async () => {
        const oldExecutor = await settlementInstance.getExecutor.call();
        await settlementInstance.setExecutor(custodianMocks.EXCHANGE, {from: custodianMocks.ADMIN});
        const newExecutor = await settlementInstance.getExecutor.call();
        assert(oldExecutor === custodianMocks.EXECUTOR);
        assert(newExecutor === custodianMocks.EXCHANGE);        
      });
      it('fails when not executed by admin and keeps previous state', async () => {
        const oldExecutor = await settlementInstance.getExecutor.call();
        await truffleAssert.fails(settlementInstance.setExecutor(custodianMocks.EXCHANGE, {from: custodianMocks.JPM}));
        const newExecutor = await settlementInstance.getExecutor.call();
        assert(oldExecutor === newExecutor);
      });
    });
    describe('setAddressAllowable', () => {
      it('sets address as allowed', async () => {
        const previousState = await settlementInstance.getAddressAllowable.call(custodianMocks.BOA);
        await settlementInstance.setAddressAllowable(custodianMocks.BOA, {from: custodianMocks.ADMIN});
        const newState = await settlementInstance.getAddressAllowable.call(custodianMocks.BOA);
        assert(previousState === false);
        assert(newState === true);        
      });
      it('fails when not executed by admin and keeps previous state', async () => {
        const previousState = await settlementInstance.getAddressAllowable.call(custodianMocks.BOA);
        await truffleAssert.fails(settlementInstance.setAddressAllowable(custodianMocks.BOA, {from: custodianMocks.JPM}));
        const newState = await settlementInstance.getAddressAllowable.call(custodianMocks.BOA);
        assert(previousState === newState);
      });
    });
    describe('setTokenAllowable', () => {
      it('sets token address as allowed', async () => {
        const previousState = await settlementInstance.getTokenAllowable.call(token1Instance.address);
        await settlementInstance.setTokenAllowable(token1Instance.address, {from: custodianMocks.ADMIN});
        const newState= await settlementInstance.getTokenAllowable.call(token1Instance.address);
        assert(previousState === false);
        assert(newState === true);        
      });
      it('fails when not executed by admin and keeps previous state', async () => {
        const previousState = await settlementInstance.getTokenAllowable.call(token1Instance.address);
        await truffleAssert.fails(settlementInstance.setTokenAllowable(token1Instance.address, {from: custodianMocks.JPM}));
        const newState = await settlementInstance.getTokenAllowable.call(token1Instance.address);
        assert(previousState === newState);
      });
    });
    describe('pausable', () => {
      it('pauses and unpauses the contract when called', async () => {
        const pausableState = await settlementInstance.paused.call();
        assert(pausableState === false);
        await truffleAssert.passes(settlementInstance.pause({from: custodianMocks.ADMIN}));
        const eventsPaused = await settlementInstance.getPastEvents('Paused');
        assert(eventsPaused.length === 1);
        const newPausableState = await settlementInstance.paused.call();
        assert(newPausableState === true);
        await truffleAssert.fails(settlementInstance.pause({from: custodianMocks.ADMIN}));
        await truffleAssert.passes(settlementInstance.unpause({from: custodianMocks.ADMIN}));
        const eventsUnpaused = await settlementInstance.getPastEvents('Unpaused');
        assert(eventsUnpaused.length === 1);
        const unpausedState = await settlementInstance.paused.call();
        assert(unpausedState == false);
      });
      it('only admin can pause and unpause', async () => {
        const pausableState = await settlementInstance.paused.call();
        assert(pausableState === false);
        await truffleAssert.fails(settlementInstance.pause({from: custodianMocks.JPM}));
        await truffleAssert.passes(settlementInstance.pause({from: custodianMocks.ADMIN}));
        await truffleAssert.fails(settlementInstance.unpause({from: custodianMocks.JPM}));
      });
    });
    describe('delete Settlement', () => {
      it ('deletes and unlocks funds when previously authorized and executed by admin', async () => {
        await setCustodiansAndTokensAsAllowable([custodianMocks.BOA, custodianMocks.JPM], [token1Instance.address, token2Instance.address]);
        //Deposits tokens to custodian approves tokens and deposit funds
        await approveAndDepositTokens([token1Instance, token2Instance], [600, 300], custodianMocks.JPM);
        //Creates Pending Settlement from JPM to BOA
        await truffleAssert.passes(settlementInstance.createPendingSettlement(0, custodianMocks.JPM, custodianMocks.BOA, [token1Instance.address, token2Instance.address], 
          [600, 300], {from: custodianMocks.EXECUTOR}));

        await settlementInstance.authorizeSettlement(0, {from: custodianMocks.JPM});
        var lockedBalanceAfterAuth = await settlementInstance.getLockedBalanceOfToken.call(custodianMocks.JPM, token1Instance.address);
        var balanceAfterAuth = await settlementInstance.getBalanceOfToken.call(custodianMocks.JPM, token1Instance.address);
        var afterApproval = await settlementInstance.getSettlementData.call(0);
        assert(lockedBalanceAfterAuth == "600");
        assert(balanceAfterAuth == "0");
        assert(afterApproval[4] == true); //authorization boolean

        await truffleAssert.passes(settlementInstance.deleteSettlement(0, {from : custodianMocks.ADMIN}));
        var lockedBalanceAfterDeletionToken1 = await settlementInstance.getLockedBalanceOfToken.call(custodianMocks.JPM, token1Instance.address);
        var balanceAfterDeletionToken1 = await settlementInstance.getBalanceOfToken.call(custodianMocks.JPM, token1Instance.address);
        var lockedBalanceAfterDeletionToken2 = await settlementInstance.getLockedBalanceOfToken.call(custodianMocks.JPM, token2Instance.address);
        var balanceAfterDeletionToken2 = await settlementInstance.getBalanceOfToken.call(custodianMocks.JPM, token2Instance.address);
        assert(lockedBalanceAfterDeletionToken1 == "0");
        assert(balanceAfterDeletionToken1 == "600");
        assert(lockedBalanceAfterDeletionToken2 == "0");
        assert(balanceAfterDeletionToken2 == "300");
      });
      it ('deletes settlement when executed by admin', async () => {
        await setCustodiansAndTokensAsAllowable([custodianMocks.BOA, custodianMocks.JPM], [token1Instance.address, token2Instance.address]);
        //Deposits tokens to custodian approves tokens and deposit funds
        await approveAndDepositTokens([token1Instance, token2Instance], [600, 300], custodianMocks.JPM);
        //Creates Pending Settlement from JPM to BOA
        await truffleAssert.passes(settlementInstance.createPendingSettlement(0, custodianMocks.JPM, custodianMocks.BOA, [token1Instance.address, token2Instance.address], 
          [600, 300], {from: custodianMocks.EXECUTOR}));

        await truffleAssert.passes(settlementInstance.deleteSettlement(0, {from : custodianMocks.ADMIN}));
        var lockedBalanceAfterDeletionToken1 = await settlementInstance.getLockedBalanceOfToken.call(custodianMocks.JPM, token1Instance.address);
        var balanceAfterDeletionToken1 = await settlementInstance.getBalanceOfToken.call(custodianMocks.JPM, token1Instance.address);
        var lockedBalanceAfterDeletionToken2 = await settlementInstance.getLockedBalanceOfToken.call(custodianMocks.JPM, token2Instance.address);
        var balanceAfterDeletionToken2 = await settlementInstance.getBalanceOfToken.call(custodianMocks.JPM, token2Instance.address);
        assert(lockedBalanceAfterDeletionToken1 == "0");
        assert(balanceAfterDeletionToken1 == "600");
        assert(lockedBalanceAfterDeletionToken2 == "0");
        assert(balanceAfterDeletionToken2 == "300");
      });
      it ('can only be executed by admin', async () => {
        await setCustodiansAndTokensAsAllowable([custodianMocks.BOA, custodianMocks.JPM], [token1Instance.address, token2Instance.address]);
        //Deposits tokens to custodian approves tokens and deposit funds
        await approveAndDepositTokens([token1Instance, token2Instance], [600, 300], custodianMocks.JPM);
        //Creates Pending Settlement from JPM to BOA
        await truffleAssert.passes(settlementInstance.createPendingSettlement(0, custodianMocks.JPM, custodianMocks.BOA, [token1Instance.address, token2Instance.address], 
          [600, 300], {from: custodianMocks.EXECUTOR}));

        await truffleAssert.fails(settlementInstance.deleteSettlement(0, {from : custodianMocks.JPM}));
      });
    });
    describe('change ownership', () => {
      it ('changes admin when executed by admin', async () => {
        await truffleAssert.passes(settlementInstance.changeOwnership(custodianMocks.JPM, {from: custodianMocks.ADMIN}));
        await truffleAssert.fails(settlementInstance.changeOwnership(custodianMocks.JPM, {from: custodianMocks.ADMIN})); 
      });
      it ('fails when not executed by admin', async () => {
        await truffleAssert.fails(settlementInstance.changeOwnership(custodianMocks.JPM, {from: custodianMocks.JPM})); 
      });
    })
  });
});