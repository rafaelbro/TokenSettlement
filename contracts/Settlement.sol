// SPDX-License-Identifier: MIT
// Tells the Solidity compiler to compile only from v0.8.13 to v0.9.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./AccessControl.sol";
import './SharedStructs.sol';
import './SharedStructs.sol';

import './SharedStructs.sol';

struct SettlementStruct {
        address debtor;
        address creditor;
        SharedStructs.TokenStruct[] transactedTokens;
        SharedStructs.TokenStruct[] releasedFromDebtorTokens;
        SharedStructs.TokenStruct[] releasedFromCreditorTokens;
        bool exists;
        bool authorized;
}

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint256 value) external returns (bool);
    function withdraw(uint _amount) external;
}

contract Settlement {
    using SafeERC20 for IERC20;    

    address public owner;
    address public executor;
    address public WETH_address;
    IWETH public weth;

    AccessControl accessControl;
    event PendingSettlement(uint256 settlementUUID, address debtor, address creditor);
    event ExecutedSettlement(uint256 settlementUUID, address debtor, address creditor);
    event Deposit(address depositor, address token,  uint256 depositedAmount, uint256 currentAmount);
    event Redemption(address depositor, address token,  uint256 depositedAmount, uint256 currentAmount);
    event CustodianSignature(uint settlementUUID);
    event Locked(address depositor, address token,  uint256 lockedAmount, uint256 currentAmount);
    event Unlocked(address depositor, address token,  uint256 lockedAmount);
    event DeleteSettlement(uint256 settlementUUID);
    event ReleaseFunds(address settlementUUID);
    event ChangeOwnership(address newOwner);




    mapping(address => mapping (address => uint256)) private custodianBalances;
    mapping(address => mapping (address => uint256)) private lockedCustodianBalances;
    mapping(uint256 => SettlementStruct) private custodianSettlements;

    constructor(address AccessControlAddress, address executorAddress, address _wEthAddress){
        owner = msg.sender;
        checkZeroAddress(executorAddress);
        executor = executorAddress;
        checkZeroAddress(AccessControlAddress);
        accessControl = AccessControl(AccessControlAddress);
        WETH_address = _wEthAddress;
        weth = IWETH(WETH_address);
        //_paused = false;
    }

    modifier onlyOwner {
        require(msg.sender == owner, "Not contract owner");
        _;
    }

    modifier onlyExecutor {
        require(msg.sender == executor, "Not contract executor");
        _;
    }

    function checkZeroAddress(address _address) internal pure {
        require (_address != address(0), "Invalid address");
    }

    function deposit(address _tokenAddress, uint256 _amount) public {
        accessControl.onlyAllowed(msg.sender);
        accessControl.onlyAllowedToken(_tokenAddress);
        IERC20 token = IERC20(_tokenAddress);
        token.safeTransferFrom(msg.sender, address(this), _amount);
        if (accessControl.isBrickAndMortar(msg.sender)){
            custodianBalances[msg.sender][_tokenAddress] += _amount;
            emit Deposit(msg.sender, _tokenAddress, _amount, custodianBalances[msg.sender][_tokenAddress]);
        } else {
            lockedCustodianBalances[msg.sender][_tokenAddress] += _amount;
            emit Locked(msg.sender, _tokenAddress, _amount, lockedCustodianBalances[msg.sender][_tokenAddress]);
        }                
    }

    receive() external payable {
        accessControl.onlyAllowed(msg.sender);
        require(msg.value > 0, "No ETH sent");
        uint msgValue = msg.value;
        weth.deposit{value: msg.value}();
        if (accessControl.isBrickAndMortar(msg.sender)){
            custodianBalances[msg.sender][WETH_address] += msgValue;
            emit Deposit(msg.sender, WETH_address, msgValue, custodianBalances[msg.sender][WETH_address]);
        } else {
            lockedCustodianBalances[msg.sender][WETH_address] += msgValue;
            emit Locked(msg.sender, WETH_address, msgValue, lockedCustodianBalances[msg.sender][WETH_address]);
        }
    }

    function createPendingSettlement(uint256 _settlementUUID, address _debtor, address _creditor, SharedStructs.TokenStruct[] memory _transactedTokens, 
        SharedStructs.TokenStruct[] memory _releasedFromDebtor, SharedStructs.TokenStruct[] memory _releasedFromCreditor) external onlyExecutor /*whenNotPaused*/ {
        require(!custodianSettlements[_settlementUUID].exists, "Settlement already exists");
        accessControl.validateSettlement(_creditor, _debtor);
        SettlementStruct storage newSettlement = custodianSettlements[_settlementUUID];
        newSettlement.debtor = _debtor;
        newSettlement.creditor = _creditor;
        newSettlement.exists = true;
        newSettlement.authorized = false;
        for (uint256 i = 0; i < _transactedTokens.length; i++) {
            require(accessControl.getTokenAllowable(_transactedTokens[i].tokenAddress), "not allowed token");
            newSettlement.transactedTokens.push(_transactedTokens[i]);
        }
        if(_releasedFromDebtor.length > 0){
            require(accessControl.isVirtualCustodian(_debtor), "not VC to have funds released");
            for (uint256 i = 0; i < _releasedFromDebtor.length; i++) {
                require(accessControl.getTokenAllowable(_releasedFromDebtor[i].tokenAddress), "not allowed token");
                newSettlement.releasedFromDebtorTokens.push(_releasedFromDebtor[i]);
            }
        }
        if(_releasedFromCreditor.length > 0){
            require(accessControl.isVirtualCustodian(_creditor), "not VC to have funds released");        
            for (uint256 i = 0; i < _releasedFromCreditor.length; i++) {
                require(accessControl.getTokenAllowable(_releasedFromCreditor[i].tokenAddress), "not allowed token");
                newSettlement.releasedFromCreditorTokens.push(_releasedFromCreditor[i]);
            }
        }
        emit PendingSettlement(_settlementUUID, _debtor, _creditor);
    }

    function authorizeSettlement(uint256 _settlementUUID) public {
        accessControl.onlyAllowed(msg.sender);
        require(!custodianSettlements[_settlementUUID].authorized, "settlement already authorized");
        require(_mappingObjectExists(_settlementUUID), "Inexistent settlement");
        if (accessControl.isBrickAndMortar(msg.sender)) {
            require(msg.sender == custodianSettlements[_settlementUUID].debtor, "Address is not the debtor");
            _lockFunds(_settlementUUID);
        }
        else if (accessControl.isVirtualCustodian(custodianSettlements[_settlementUUID].debtor)) {
            require(accessControl.isAuditor(msg.sender));
        } else {
            revert("Invalid custodian category");
        }
        custodianSettlements[_settlementUUID].authorized = true;
        emit CustodianSignature(_settlementUUID);
    }

    function authorizeMultiple(uint256[] memory _settlementUUIDs) public {
        for (uint256 i = 0; i< _settlementUUIDs.length; i++) {
            authorizeSettlement(_settlementUUIDs[i]);
        }
    }

    function executeSettlement(uint256[] memory _executedIds) external onlyExecutor {
        for (uint256 settlementIndex= 0; settlementIndex < _executedIds.length; settlementIndex++) {
            require(_mappingObjectExists(_executedIds[settlementIndex]), "Inexistent settlement");
            require(custodianSettlements[_executedIds[settlementIndex]].authorized, "Settlement not signed");
            _settle(_executedIds[settlementIndex]);
            _freeStorage(_executedIds[settlementIndex]);
        }
    }

    function _mappingObjectExists(uint256 settlementUUID) private view returns (bool){
        return custodianSettlements[settlementUUID].exists == true ? true : false;
    }

    function _settle(uint256 _settlementUUID) private {
        SettlementStruct storage settlement = custodianSettlements[_settlementUUID];
        for (uint index = 0; index < settlement.transactedTokens.length; index++) {
            if(accessControl.isBrickAndMortar(settlement.creditor)) {
            //moves from locked debtor to unlocked creditor if creditor is category 1(BRICK)
                lockedCustodianBalances[settlement.debtor][settlement.transactedTokens[index].tokenAddress] -= settlement.transactedTokens[index].tokenAmount;
                custodianBalances[settlement.creditor][settlement.transactedTokens[index].tokenAddress] += settlement.transactedTokens[index].tokenAmount;
            } else if (accessControl.isVirtualCustodian(settlement.creditor)) {
                //moves from locked debtor to locked creditor if creditor is category 2(VC)
                lockedCustodianBalances[settlement.debtor][settlement.transactedTokens[index].tokenAddress] -= settlement.transactedTokens[index].tokenAmount;
                lockedCustodianBalances[settlement.creditor][settlement.transactedTokens[index].tokenAddress] += settlement.transactedTokens[index].tokenAmount;
            }
        }
        if (settlement.releasedFromDebtorTokens.length != 0) _unlockFunds(settlement.debtor, settlement.releasedFromDebtorTokens);
        if (settlement.releasedFromCreditorTokens.length != 0) _unlockFunds(settlement.creditor, settlement.releasedFromCreditorTokens);
        emit ExecutedSettlement(_settlementUUID, settlement.debtor, settlement.creditor);
    }

    function _lockFunds(uint256 _settlementUUID) private {
        SettlementStruct storage settlement = custodianSettlements[_settlementUUID];
        for (uint index = 0; index < settlement.transactedTokens.length; index++) {
            //moves from unlocked debtor to locked debtor
            custodianBalances[settlement.debtor][settlement.transactedTokens[index].tokenAddress] -= settlement.transactedTokens[index].tokenAmount;
            lockedCustodianBalances[settlement.debtor][settlement.transactedTokens[index].tokenAddress] += settlement.transactedTokens[index].tokenAmount;
        }
    }

    function _freeStorage(uint256 key) private {
        delete custodianSettlements[key].transactedTokens;
        delete custodianSettlements[key].releasedFromDebtorTokens;
        delete custodianSettlements[key].releasedFromCreditorTokens;

        delete custodianSettlements[key].debtor;
        delete custodianSettlements[key].creditor;
        custodianSettlements[key].exists = false;
        custodianSettlements[key].authorized = false;
    }

    function redeem(address _tokenAddress, uint256 _amount) public {
        accessControl.onlyAllowed(msg.sender);
        IERC20 token = IERC20(_tokenAddress);
        require(_amount <= custodianBalances[msg.sender][_tokenAddress], "Insuficient funds");
        custodianBalances[msg.sender][_tokenAddress] -= _amount;
        if(_tokenAddress == WETH_address) {
            require(weth.transfer(msg.sender,_amount), "Failed to transfer");
        } else {
            token.safeTransfer(msg.sender, _amount);
        }
        emit Redemption(msg.sender, _tokenAddress, _amount, custodianBalances[msg.sender][_tokenAddress]);        
    }

    function getBalancesOfToken(address _custodianAddress, address _tokenAddress) public view returns (uint256 balance, uint256 lockedBalance){
        return (custodianBalances[_custodianAddress][_tokenAddress], lockedCustodianBalances[_custodianAddress][_tokenAddress]);
    }

    function getSettlementData(uint256 _settlementId) public view returns (address debtor, address creditor, 
        SharedStructs.TokenStruct[] memory transactedTokens, SharedStructs.TokenStruct[] memory releasedFromDebtorTokens, 
        SharedStructs.TokenStruct[] memory releasedFromCreditorTokens, bool authorized) {
        return (custodianSettlements[_settlementId].debtor, custodianSettlements[_settlementId].creditor, 
            custodianSettlements[_settlementId].transactedTokens, custodianSettlements[_settlementId].releasedFromDebtorTokens,
            custodianSettlements[_settlementId].releasedFromCreditorTokens, 
            custodianSettlements[_settlementId].authorized);
    }

    function getContractData() public view returns (address executorAddress, address adminAddress){
        return (executor, owner);
    }

    function _unlockFunds(address entity, SharedStructs.TokenStruct[] memory tokens) internal {
        for (uint index = 0; index < tokens.length; index++) {
            lockedCustodianBalances[entity][tokens[index].tokenAddress] -= tokens[index].tokenAmount;
            custodianBalances[entity][tokens[index].tokenAddress] += tokens[index].tokenAmount;
        }
    }
    
    function deleteSettlement(uint256 _settlementUUID) external onlyOwner {
        if (!accessControl.isVirtualCustodian(custodianSettlements[_settlementUUID].debtor)){
            //Only non VC users need to move funds
            if (custodianSettlements[_settlementUUID].authorized){
            SettlementStruct storage settlement = custodianSettlements[_settlementUUID];
                for (uint index = 0; index < settlement.transactedTokens.length; index++) {
                    //moves from locked debtor to unlocked debtor
                    lockedCustodianBalances[settlement.debtor][settlement.transactedTokens[index].tokenAddress] -= settlement.transactedTokens[index].tokenAmount;      
                    custodianBalances[settlement.debtor][settlement.transactedTokens[index].tokenAddress] += settlement.transactedTokens[index].tokenAmount; 
                }
            }
        }        
        _freeStorage(_settlementUUID);
        emit DeleteSettlement(_settlementUUID);

    }

    function releaseFunds(address custodianAddress, address[] calldata tokenAddresses) external onlyOwner {
        require(accessControl.isVirtualCustodian(custodianAddress), "cannot release non VCs");
        for(uint index = 0; index < tokenAddresses.length; index++){
            uint amount = lockedCustodianBalances[custodianAddress][tokenAddresses[index]];
            lockedCustodianBalances[custodianAddress][tokenAddresses[index]] -= amount;
            custodianBalances[custodianAddress][tokenAddresses[index]] += amount;
        }
        emit ReleaseFunds(custodianAddress);
    }

    function changeOwnership(address _ownerAddress) external onlyOwner {
        checkZeroAddress(_ownerAddress);
        owner = _ownerAddress;
        emit ChangeOwnership(_ownerAddress);
    }
}
