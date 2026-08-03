// SPDX-License-Identifier: MIT
// Tells the Solidity compiler to compile only from v0.8.13 to v0.9.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Token1 is ERC20{
    constructor() ERC20("RESIDUAL1", "RES1"){
        _mint(msg.sender,1000*10**18);
    }
}