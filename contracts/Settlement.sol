// SPDX-License-Identifier: MIT
// Tells the Solidity compiler to compile only from v0.8.13 to v0.9.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

struct SettlementStruct {
        address debtor;
        address creditor;
        address[] tokens;
        uint256[] amounts;
        bool exists;
        bool authorized;
        bool releaseCreditor;
        bool releaseDebtor;
}

contract Settlement {    

    address private owner;
    address private executor;
    bool private _paused;
    event PendingSettlement(uint256 settlementUUID, address debtor, address creditor);
    event ExecutedSettlement(uint256 settlementUUID, address debtor, address creditor);
    event Deposit(address depositor, address token,  uint256 depositedAmount, uint256 currentAmount);
    event Redemption(address depositor, address token,  uint256 depositedAmount, uint256 currentAmount);
    event Paused(address account);
    event Unpaused(address account);
    event CustodianSignature(uint settlementUUID);
    event Locked(address depositor, address token,  uint256 lockedAmount);
    event Unlocked(address depositor, address token,  uint256 lockedAmount);


    mapping(address => mapping (address => uint256)) private custodianBalances;
    mapping(address => mapping (address => uint256)) private lockedCustodianBalances;
    mapping(uint256 => SettlementStruct) private custodianSettlements;
    mapping(address => bool) private custodianAddresses; 
    mapping(address => uint8) private custodianCategory; // 0 - Big custodians  1 - Individuals 10 - Marked as releasable
    mapping(address => bool) private allowableTokens;

    constructor(){
        owner = msg.sender;
        _paused = false;
    }

    modifier onlyOwner {
        require(msg.sender == owner, "Not contract owner");
        _;
    }

    modifier onlyExecutor {
        require(msg.sender == executor, "Not contract executor");
        _;
    }

    modifier onlyAllowed {
        require(custodianAddresses[msg.sender] == true, "Address not allowed");
        _;
    }

    modifier onlyAllowedToken(address tokenAddress) {
        require(allowableTokens[tokenAddress] == true, "Token not allowed");
        _;
    }

    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    modifier whenPaused() {
        _requirePaused();
        _;
    }
    
    function _requirePaused() internal view virtual {
        require(paused(), "Pausable: not paused");
    }

    function deposit(address tokenAddress, uint256 amount) public onlyAllowed onlyAllowedToken(tokenAddress) {
        IERC20 token = IERC20(tokenAddress);
        SafeERC20.safeTransferFrom(token, msg.sender, address(this), amount);
        (overflow, custodianBalances[msg.sender][tokenAddress]) = SafeMath.tryAdd(custodianBalances[msg.sender][tokenAddress], amount);
        require(overflow, "Operation overflow");
        emit Deposit(msg.sender, tokenAddress, amount, custodianBalances[msg.sender][tokenAddress]);
    }

    function lockFunds(address tokenAddress, uint256 amount) public onlyAllowed onlyAllowedToken(tokenAddress) {
        bool operationOverflow = false;
        if(custodianCategory[msg.sender] == 10) custodianCategory [msg.sender] == 1; //relocks custodian after marked for release
        require(custodianCategory[msg.sender] == 1, "This custodian category cannot lock funds");
        //moves from unlocked debtor to locked debtor
        (operationOverflow, custodianBalances[msg.sender][tokenAddress], lockedCustodianBalances[msg.sender][tokenAddress]) = 
            _moveFunds(custodianBalances[msg.sender][tokenAddress], lockedCustodianBalances[msg.sender][tokenAddress], amount);
        require(operationOverFlow, "Could not lock due to insuficient funds");
        emit Locked(msg.sender, tokenAddress, amount);
    }

    function unlockFunds(address tokenAddress) public {
        bool operationOverflow = false;
        require(custodianCategory[msg.sender] == 10, "This custodian is not marked for release");
        //releases funds of token address
        (operationOverflow, custodianBalances[msg.sender][tokenAddress]) = SafeMath.tryAdd(custodianBalances[msg.sender][tokenAddress], lockedCustodianBalances[msg.sender][tokenAddress]);
        lockedCustodianBalances[msg.sender][tokenAddress] = 0;
        require(operationOverFlow, "Could not unlock due to overflow");
        emit Unlocked(msg.sender, tokenAddress);
    }

    function createPendingSettlement(uint256 settlementUUID, address debtor, address creditor, address[] memory tokenAddresses, 
        uint256[] memory tokenAmounts, bool releaseCreditor, bool releaseDebtor) external onlyExecutor whenNotPaused {
        require ((custodianAddresses[creditor] && custodianAddresses[debtor]), "Invalid creditor/debtor");
        require(tokenAddresses.length == tokenAmounts.length, "Invalid tokens addresses and amount pairs");
        require(!custodianSettlements[settlementUUID].exists, "Settlement already exists");
        for(uint index = 0; index < tokenAddresses.length; index++) {
            require(allowableTokens[tokenAddresses[index]], "Invalid token used");
        }
        custodianSettlements[settlementUUID] = SettlementStruct(debtor, creditor, tokenAddresses, tokenAmounts, true, false, releaseCreditor, releaseDebtor);
        emit PendingSettlement(settlementUUID, debtor, creditor);
    }

    function authorizeSettlement(uint256 settlementUUID) public onlyAllowed {
        require(_mappingObjectExists(settlementUUID), "Tried to sign inexistent settlement");
        require(custodianCategory[custodianSettlements[settlementUUID].debtor], "This custodian type cannot authorize settlements");
        require(msg.sender == custodianSettlements[settlementUUID].debtor, "Address is not the debtor of the settlement");
        custodianSettlements[settlementUUID].authorized = true;
        _lockFunds(settlementUUID);
        emit CustodianSignature(settlementUUID);
    }

    function executeSettlement(uint256[] memory executedIds) external onlyExecutor whenNotPaused {
        for (uint256 settlementIndex= 0; settlementIndex < executedIds.length; settlementIndex++) {
            require(_mappingObjectExists(executedIds[settlementIndex]), "Tried to settle inexistent settlement");
            //Debtor is either custodian type 0 that requires authorization or 1 that doesn't TODO: DEFINE A BETTER RULE
            require(custodianSettlements[executedIds[settlementIndex]].authorized || 
                custodianCategory[custodianSettlements[executedIds[settlementIndex]].debtor] == 1, "Settlement needs to be signed before executed");
            _settle(executedIds[settlementIndex]);
            _freeStorage(executedIds[settlementIndex]);
        }
    }

    function _mappingObjectExists(uint256 settlementUUID) private view returns (bool){
        return custodianSettlements[settlementUUID].exists == true ? true : false;
    }

    function _settle(uint256 settlementUUID) private {
        bool overflow = true;
        SettlementStruct storage settlement = custodianSettlements[settlementUUID];
        require(custodianCategory[settlement.debtor] != 10 && custodianCategory[settlement.creditor] != 10, "creditor or debtor marked as released");
        for (uint index = 0; index < settlement.tokens.length; index++) {
            bool operationOverflow = false;
            if(custodianCategory[settlement.creditor] == 0) {
            //moves from locked debtor to unlocked creditor if creditor is category 0 or if funds are marked for release
                (operationOverflow, lockedCustodianBalances[settlement.debtor][settlement.tokens[index]], custodianBalances[settlement.creditor][settlement.tokens[index]]) = 
                        _moveFunds(lockedCustodianBalances[settlement.debtor][settlement.tokens[index]], custodianBalances[settlement.creditor][settlement.tokens[index]], settlement.amounts[index]);
                overflow = operationOverflow && overflow;
            } else if (custodianCategory[settlement.creditor] == 1) {
                //moves from locked debtor to locked creditor if creditor is category 1
                (operationOverflow, lockedCustodianBalances[settlement.debtor][settlement.tokens[index]], lockedCustodianBalances[settlement.creditor][settlement.tokens[index]]) = 
                    _moveFunds(lockedCustodianBalances[settlement.debtor][settlement.tokens[index]], lockedCustodianBalances[settlement.creditor][settlement.tokens[index]], settlement.amounts[index]);
                overflow = operationOverflow && overflow;
            }
        }
        if (settlement.releaseCreditor == true && custodianCategory[settlement.creditor] == 1) custodianCategory[settlement.creditor] = 10;
        if (settlement.releaseDebtor == true && custodianCategory[settlement.debtor] == 1) custodianCategory[settlement.debtor] = 10;
        require(overflow, "Could not settle due to insuficient funds");
        emit ExecutedSettlement(settlementUUID, settlement.debtor, settlement.creditor);
    }

    function _lockFunds(uint256 settlementUUID) private {
        bool overflow = true;
        SettlementStruct storage settlement = custodianSettlements[settlementUUID];
        for (uint index = 0; index < settlement.tokens.length; index++) {
            bool operationOverflow = false;
            //moves from unlocked debtor to locked debtor
            (operationOverflow, custodianBalances[settlement.debtor][settlement.tokens[index]], lockedCustodianBalances[settlement.debtor][settlement.tokens[index]]) = 
                    _moveFunds(custodianBalances[settlement.debtor][settlement.tokens[index]], lockedCustodianBalances[settlement.debtor][settlement.tokens[index]], settlement.amounts[index]);
            overflow = operationOverflow && overflow;
        }
        require(overflow, "Could not lock due to insuficient funds");
    }

    function _freeStorage(uint256 key) private {
        SettlementStruct memory emptyStruct;
        custodianSettlements[key] = emptyStruct;
    }

    function redeem(address tokenAddress, uint256 amount) public onlyAllowed {
        IERC20 token = IERC20(tokenAddress);
        require(amount <= custodianBalances[msg.sender][tokenAddress], "Insuficient funds");
        (, custodianBalances[msg.sender][tokenAddress]) = SafeMath.trySub(custodianBalances[msg.sender][tokenAddress], amount);
        SafeERC20.safeTransfer(token, msg.sender, amount);
        emit Redemption(msg.sender, tokenAddress, amount, custodianBalances[msg.sender][tokenAddress]);        
    }

    function getBalanceOfToken(address custodianAddress, address tokenAddress) public view returns (uint256){
        return custodianBalances[custodianAddress][tokenAddress];
    }

    function getLockedBalanceOfToken(address custodianAddress, address tokenAddress) public view returns (uint256){
        return lockedCustodianBalances[custodianAddress][tokenAddress];
    }

    function getSettlementData(uint256 settlementId) public view returns (address debtor, address creditor, 
        address[] memory tokens, uint256[] memory amounts, bool authorized) {
        return (custodianSettlements[settlementId].debtor, custodianSettlements[settlementId].creditor, 
            custodianSettlements[settlementId].tokens, custodianSettlements[settlementId].amounts, custodianSettlements[settlementId].authorized);
    }

    function setExecutor(address executorAddress) external onlyOwner {
        executor = executorAddress;
    }

    function getExecutor()  public view returns (address) {
        return executor;
    }

    function setCustodianAllowable(address custodianAddress, uint8 custodianCategory) external onlyOwner {
        custodianAddresses[custodianAddress] = true;
        custodianCategory[custodianAddresses] = custodianCategory;
    }

    function removeAddressAllowable(address custodianAddress) external onlyOwner {
        custodianAddresses[custodianAddress] = false;
    }

    function getAddressAllowable(address custodianAddress) public view returns (bool) {
        return custodianAddresses[custodianAddress];
    }

    function setTokenAllowable(address tokenAddress) external onlyOwner {
        allowableTokens[tokenAddress] = true;
    }

    function removeTokenAllowable(address tokenAddress) external onlyOwner {
        allowableTokens[tokenAddress] = false;
    }

    function getTokenAllowable(address tokenAddress) public view returns (bool) {
        return allowableTokens[tokenAddress];
    }

    function paused() public view virtual returns (bool) {
        return _paused;
    }

    function _requireNotPaused() internal view virtual {
        require(!paused(), "Pausable: paused");
    }

    function pause() external whenNotPaused onlyOwner {
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external whenPaused onlyOwner {
        _paused = false;
        emit Unpaused(msg.sender);
    }
    
    function changeOwnership(address ownerAddress) external onlyOwner {
        owner = ownerAddress;
    }

    function getOwner() public view returns (address) {
        return owner;
    }

    function _moveFunds(uint256 debtorAmt, uint256 creditorAmt, uint256 amt) internal pure 
        returns (bool overflow, uint256 debtorBalance, uint256 creditorBalance) {
        bool overflowSub = false;
        bool overflowAdd = false;           
        (overflowSub , debtorBalance) = SafeMath.trySub(debtorAmt, amt);
        (overflowAdd, creditorBalance) = SafeMath.tryAdd(creditorAmt, amt);
        return (overflowSub && overflowAdd, debtorBalance, creditorBalance);
    }

    function deleteSettlement(uint256 settlementUUID) external onlyOwner {
        if (custodianSettlements[settlementUUID].authorized){
            bool overflow = true;
            SettlementStruct storage settlement = custodianSettlements[settlementUUID];
            for (uint index = 0; index < settlement.tokens.length; index++) {
                bool operationOverflow = false;
                //moves from locked debtor to unlocked debtor      
                (operationOverflow, lockedCustodianBalances[settlement.debtor][settlement.tokens[index]], custodianBalances[settlement.debtor][settlement.tokens[index]]) = 
                    _moveFunds(lockedCustodianBalances[settlement.debtor][settlement.tokens[index]], custodianBalances[settlement.debtor][settlement.tokens[index]], settlement.amounts[index]);
                overflow = operationOverflow && overflow;
            }
            require(overflow, "Could not settle due to insuficient funds");
        }
        _freeStorage(settlementUUID);
    }
}