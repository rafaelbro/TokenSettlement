/**
 * Use this file to configure your truffle project. It's seeded with some
 * common settings for different networks and features like migrations,
 * compilation and testing. Uncomment the ones you need or modify
 * them to suit your project as necessary.
 *
 * More information about configuration can be found at:
 *
 * trufflesuite.com/docs/advanced/configuration
 *
 * To deploy via Infura you'll need a wallet provider (like @truffle/hdwallet-provider)
 * to sign your transactions before they're sent to a remote public node. Infura accounts
 * are available for free at: infura.io/register.
 *
 * You'll also need a mnemonic - the twelve word phrase the wallet uses to generate
 * public/private key pairs. If you're publishing your code to GitHub make sure you load this
 * phrase from a file you've .gitignored so it doesn't accidentally become public.
 *
 */

// const HDWalletProvider = require('@truffle/hdwallet-provider');
// const infuraKey = "fj4jll3k.....";
//
// const fs = require('fs');
// const mnemonic = fs.readFileSync(".secret").toString().trim();
const HDWalletProvider = require('@truffle/hdwallet-provider');
const fs = require('fs');

var NonceTrackerSubprovider = require("web3-provider-engine/subproviders/nonce-tracker")


// GET A NEW VANITY-ETH: https://vanity-eth.tk/
// VANITY-ETH ADDRESS: 0x9f1A2456e19565260dDe8b70837189aE63E2409a
// VANITY-ETH ANDRESS PRIV KEY: 961706d001210e16f60bcccb14c390f93deb97d3f89e37b58f50b3a7c16aa64a

// GET BNB FOR THE CREATED ADDRESS: https://testnet.binance.org/faucet-smart
// VALIDATE THE RECEIVED BNB IN THE TESTNET: https://testnet.bscscan.com/address/<ADDRESS_GENERATED>
//b9e1e1bc3b4b48643cde5baaf02bedf055fbcd69da5b337d8e039ee75a35dff5 - > HEck
/*
const provider = new HDWalletProvider({
  privateKeys: ['b9e1e1bc3b4b48643cde5baaf02bedf055fbcd69da5b337d8e039ee75a35dff5'],
  providerOrUrl: 'https://data-seed-prebsc-1-s1.binance.org:8545'
});

const providerMainNet = new HDWalletProvider({
  privateKeys: ['b9e1e1bc3b4b48643cde5baaf02bedf055fbcd69da5b337d8e039ee75a35dff5'],
  providerOrUrl: 'https://bsc-dataseed1.binance.org'
});
const providerForFork = new HDWalletProvider({
  privateKeys: ['c480b67f2ebccdac9828d0a11ed73d388d6a76fa28ec55401ed593b7c8730f43'],
  providerOrUrl: 'http://127.0.0.1:7545'
});
*/

module.exports = {
  /**
   * Networks define how you connect to your ethereum client and let you set the
   * defaults web3 uses to send transactions. If you don't specify one truffle
   * will spin up a development blockchain for you on port 9545 when you
   * run `develop` or `test`. You can ask a truffle command to use a specific
   * network from the command line, e.g
   *
   * $ truffle test --network <network-name>
   */
  plugins: ['truffle-plugin-verify'],
  api_keys: {
    etherscan: 'YOUR_ETHERSCAN_API_KEY'
  },
  networks: {
    // Useful for testing. The `development` name is special - truffle uses it by default
    // if it's defined here and no other network is specified at the command line.
    // You should run a client (like ganache-cli, geth or parity) in a separate terminal
    // tab if you use this network and you must also set the `host`, `port` and `network_id`
    // options below to some value.
    //
    development: {
      host: '0.0.0.0',
      port: 8545,
      network_id: '*',
      gasPrice: 2000000000,
      gas: 30000000      
    },    
    testnet: {
      provider: function () { 
        var wallet = new HDWalletProvider({
          providerOrUrl: 'https://goerli.infura.io/v3/54b92e207bf34e5da5002c05c9fedc87',
          privateKeys: ['9b2f178fd587cda32608cd4c73c17ba9b83a8ba515c446af9d80e39bf6f2d7f0',
                        '6c2593c246861ba30846741878ed9e83cc346de026f1dd3249370053751d9448',
                        '384f885562d423b1fb63c4bbf76de6a0d5e120e3df80cb35425290b3d251f1c1',
                        '7d20698c0cb0ae054fd7a55a51c2d3ded26039f181e4c3d0471439d8a35afd5c',
                        'fcfde2b0435c008cc163c43588687dba8c0f257fcc046db404d27ae03c4d5bea',
                        'd78c946a1ad510d38f22b0dcdb80db4d91ec17e771f74e2680a154773d37943b'] 
        });
        var nonceTracker = new NonceTrackerSubprovider();
        wallet.engine._providers.unshift(nonceTracker);
        nonceTracker.setEngine(wallet.engine);
        return wallet;
      },
      network_id: '5',
      confirmations: 1,
      timeoutBlocks: 200,
      skipDryRun: true,
      gasPrice: 26329293992,
      gas: 10000000
    },/*
    mainnet: {
      provider: () => providerMainNet,
      network_id: 56,
      confirmations: 3,
      timeoutBlocks: 200,
      skipDryRun: true,
      gasPrice: 5000000000,
      //gas: 20000000,
    }*/
    // Another network with more advanced options...
    // advanced: {
    // port: 8777,             // Custom port
    // network_id: 1342,       // Custom network
    // gas: 8500000,           // Gas sent with each transaction (default: ~6700000)
    // gasPrice: 20000000000,  // 20 gwei (in wei) (default: 100 gwei)
    // from: <address>,        // Account to send txs from (default: accounts[0])
    // websockets: true        // Enable EventEmitter interface for web3 (default: false)
    // },
    // Useful for deploying to a public network.
    // NB: It's important to wrap the provider as a function.
    // ropsten: {
    // provider: () => new HDWalletProvider(mnemonic, `https://ropsten.infura.io/v3/YOUR-PROJECT-ID`),
    // network_id: 3,       // Ropsten's id
    // gas: 5500000,        // Ropsten has a lower block limit than mainnet
    // confirmations: 2,    // # of confs to wait between deployments. (default: 0)
    // timeoutBlocks: 200,  // # of blocks before a deployment times out  (minimum/default: 50)
    // skipDryRun: true     // Skip dry run before migrations? (default: false for public nets )
    // },
    // Useful for private networks
    // private: {
    // provider: () => new HDWalletProvider(mnemonic, `https://network.io`),
    // network_id: 2111,   // This network is yours, in the cloud.
    // production: true    // Treats this network as if it was a public net. (default: false)
    // }
  },

  // Set default mocha options here, use special reporters etc.
  mocha: {
    // timeout: 100000
  },

  // Configure your compilers
  compilers: {
    solc: {
      version: "^0.8.0",    // Fetch exact version from solc-bin (default: truffle's version)
      // docker: true,        // Use "0.5.1" you've installed locally with docker (default: false)
      // settings: {          // See the solidity docs for advice about optimization and evmVersion
      //  optimizer: {
      //    enabled: false,
      //    runs: 200
      //  },
      //  evmVersion: "byzantium"
      // }
    }
  }
};