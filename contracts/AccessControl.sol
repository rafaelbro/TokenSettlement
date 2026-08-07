// SPDX-License-Identifier: MIT
// Tells the Solidity compiler to compile only from v0.8.13 to v0.9.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import './SharedStructs.sol';
import '../libraries/Utils.sol';

contract AccessControl {    

    address public owner;
    address public auditor;
    address public settlementContract;

    bool public definedContract = false;

    mapping(address => bool) private custodianAddresses; 
    mapping(address => uint8) private custodianCategory; // 1 - Big custodians  2 - Individuals
    mapping(address => bool) private allowableTokens;
    

    event CustodianAdded(address custodianAddress, uint8 custodianCategory);

    constructor(address _auditorAddress, address _wethAddress){
        checkZeroAddress(_auditorAddress);
        auditor = _auditorAddress;
        allowableTokens[_wethAddress] = true;
        owner = msg.sender;
    }

    function onlyOwner (address sentAddress) private view {
        require(sentAddress == owner, "Not contract owner");
        return;
    }

    function checkZeroAddress(address _address) internal pure {
        require (_address != address(0), "Invalid address");
    }

    function onlySettlementAndAuditor(address settlementContractOrAuditorAddress) private view {
        require((settlementContractOrAuditorAddress == auditor) || (settlementContractOrAuditorAddress == settlementContract), "No permission to release");
        return;
    }

     function onlySettlement(address settlementContractOrAuditorAddress) private view {
        require((settlementContractOrAuditorAddress == settlementContract), "No permission to lock");
        return;
    }
    

    function onlyAllowed (address sentAddress) external view {
        require(custodianAddresses[sentAddress] == true || sentAddress == auditor, "Custodian Not allowed");
        return;
    }

    function onlyAllowedToken(address tokenAddress) external view {
        require(allowableTokens[tokenAddress] == true, "Token not allowed");
        return;
    }

    function isAuditor(address auditorAddress) external view returns (bool) {
        require(auditor == auditorAddress, "Address is not the auditor");
        return true;
    }

    function setMultipleCustodiansAllowable(address[] calldata newCustodianAddresses, uint8[] calldata custodianCategories) external {
        require(newCustodianAddresses.length == custodianCategories.length);
        onlyOwner(msg.sender);
        for (uint8 i = 0; i< newCustodianAddresses.length; i++){
            setCustodianAllowable(newCustodianAddresses[i], custodianCategories[i]);
        }
    }

    function setCustodianAllowable(address custodianAddress, uint8 custodianCategoryValue) public {
        onlyOwner(msg.sender);
        checkZeroAddress(custodianAddress);
        require(custodianAddresses[custodianAddress] == false, "custodian already added");
        require(custodianCategoryValue == 1 || custodianCategoryValue == 2, "invalid custodian category");
        custodianAddresses[custodianAddress] = true;
        custodianCategory[custodianAddress] = custodianCategoryValue;
        emit CustodianAdded(custodianAddress, custodianCategoryValue);
    }

    function getCustodianAllowable(address custodianAddress) external view returns (bool, uint8) {
        return (custodianAddresses[custodianAddress], custodianCategory[custodianAddress]);
    }

    function isVirtualCustodian(address custodianAddress) external view returns (bool) {
        return 2 == custodianCategory[custodianAddress];
    }
    function isBrickAndMortar(address custodianAddress) external view returns (bool){
        return 1 == custodianCategory[custodianAddress];
    }

    function validateSettlement(address creditor, address debtor) external view {
        require ((custodianAddresses[creditor] && custodianAddresses[debtor]), "Invalid creditor/debtor");    
    }  

    function setTokenAllowable(address tokenAddress) external {
        onlyOwner(msg.sender);
        allowableTokens[tokenAddress] = true;
    }

    function removeTokenAllowable(address tokenAddress) external {
        onlyOwner(msg.sender);
        allowableTokens[tokenAddress] = false;
    }

    function getTokenAllowable(address tokenAddress) public view returns (bool) {
        return allowableTokens[tokenAddress];
    }

    function changeOwnership(address ownerAddress) external {
        onlyOwner(msg.sender);
        checkZeroAddress(ownerAddress);
        owner = ownerAddress;
    }

    function addSettlementContractAddress(address settlementAddress) public {
        onlyOwner(msg.sender);
        require (definedContract == false, "Cannot redefine linked settlement contract");
        checkZeroAddress(settlementAddress);
        settlementContract = settlementAddress;
        definedContract = true;
    }
}
