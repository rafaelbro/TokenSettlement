# EVM Smart Contracts for CCNS (Cross Custodian Net Settlements)

Smart contracts PoC of settlement process

## Overview

This project aims to provide the ability to execute a settlement process. This happens through the execution of the following methods inside the smart contract: `createPendingSettlement` and `executeSettlement`. Those are executed off-chain by the executor and they work the following way:

`createPendingSettlement`: Receives an ID of the settlement process and native blockchain addresses of the debtor and creditor of the settlement. Along those values we need to inform in a respective array the token addresses that need to be settled for, along with the values of those associated tokens.

`executeSettlement`: Executes a previously created settlement through its ID. For this process to execute successfully we make sure that all the balances of tokens previously informed execute in a atomic transaction, and previously authorized. Which means that either all the tokens are from the debtor are transferred, in the specified amount, to the creditor, or the execution will fail.

Two other methods allow the end Customer to interact directly with the smart contract. The `deposit`, `redeem`  and `authorize` methods.

`deposit`: This allows the customer to deposit the tokens to be settled in the smart contract.

`redeem`: This allows the customer to withdraw unlocked tokens from the smart contract.

`authorize`: This allows the customer to authorize a previously created settlement on the blockchain. This process will lock the funds of the settlement until the execution of the method `executeSettlement`. It is not possible to authorize a settlement if the customer hasn't previously deposited all the funds necessary to authorize for that settlement.

## Security Features

Currently the contract has two main roles. The owner and the executor. We chose to divide the roles to increase security of the smart contract and facilitate the automation of the executor role. The responsabilities of those roles are:

#### Owner:

    - Add and remove allowable tokens with which the customers will be able to interact via deposits and withdraws.
    - Add allowable customers that will be able to interact with all the functionalities of the smart contract.
    - Pause and unpause the contract.
    - Define the address that will have the privilege to execute the creation and execution of settlements. The executor role.

#### Executor:

    - Execute the functionalities that create and execute settlements.


# Tools

    - NPM
    - Docker-compose

# How to run

 - `npm install` to install all packages
 - `docker compose up` to start a ganache local test ethereum blockchain on port 8545
 - `npm run deploy:dev` to deploy locally on the test blockchain
 - `npm run test` to run automated test suite
 - `npm run start` to interact with the local test ethereum blockchain