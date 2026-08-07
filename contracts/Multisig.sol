// SPDX-License-Identifier: MIT
// Tells the Solidity compiler to compile only from v0.8.13 to v0.9.0
pragma solidity ^0.8.0;

import "./AccessControl.sol";
import "./Settlement.sol";
/* 1 for custodian 
2 for token 
3 for deletion of settlement 
4 release funds
5 quorum changes
6 signer changes
*/
contract Multisig {

    address[] public owners;
    mapping (address => bool) public isOwner;
    uint256 public requiredSignatures;
    uint public timelock;
    AccessControl accessControl;
    Settlement settlement;
    uint constant AVERAGE_BLOCK_PER_DAY = 7200;
    uint256 STALE_TRANSACTION_BLOCKS;

    event Approved(uint transactionId, uint8 operation);
    event Revoked(uint transactionId, uint8 operation);
    event Executed(uint transactionId, uint8 operation);
    event NewTransaction(uint transactionId, uint8 operation, bool add);

    struct Custodian {
        address[] newCustodianAddress;
        uint8[] custodianCategories;
        uint256 unlockTimestamp;
        uint256 staleTimestamp;
        bool executed;
        bool add; // true to add false to remove
    }

    struct Token {
        address newTokenAddress;
        uint256 unlockTimestamp;
        uint256 staleTimestamp;
        bool executed;
        bool add; // true to add false to remove
    }

    struct SettlementTransaction {
        uint settlementUUID;
        uint256 unlockTimestamp;
        uint256 staleTimestamp;
        bool executed;
    }

    struct ReleaseFunds {
        address custodianAddress;
        address[] tokenAddresses;
        uint256 unlockTimestamp;
        uint256 staleTimestamp;
        bool executed;
    }

    struct QuorumTreshold{
        bool add;
        uint256 unlockTimestamp;
        uint256 staleTimestamp;
        bool executed;
    }

    struct Signers {
        address signer;
        bool add;
        uint256 unlockTimestamp;
        uint256 staleTimestamp;
        bool executed;
    }

    Custodian[] public CustodianTransactions;    
    Token[] public TokenTransactions;
    SettlementTransaction[] public SettlementTransactions;
    ReleaseFunds[] public ReleaseFundsTransactions;
    QuorumTreshold[] public QuorumTresholdTransactions;
    Signers[] public SignersTransactions;

    mapping(uint => mapping(uint => mapping(address => bool))) public approved;

    modifier onlyOwner(){
        require(isOwner[msg.sender], "not owner");
        _;
    }

    modifier txValid(uint _transactionId, uint8 _operation){
        bool valid = false;
        if (_operation == 1){
            valid = _transactionId < CustodianTransactions.length;
        }
        if (_operation == 2){
            valid =_transactionId < TokenTransactions.length;
        }
        if (_operation == 3){
           valid =_transactionId < SettlementTransactions.length;
        }
        if (_operation == 4){
           valid =_transactionId < ReleaseFundsTransactions.length;
        }
        if (_operation == 5){
           valid =_transactionId < QuorumTresholdTransactions.length;
        }
        if (_operation == 6){
           valid =_transactionId < SignersTransactions.length;
        }
        require(valid, "invalid tx id");
        _;
    }

    function _getTransactionTimestamps(uint _transactionId, uint8 _operationType)private view returns (uint256 unlockTimestamp, uint256 staleTimestamp){
        if (_operationType == 1){
            Custodian storage custodian = CustodianTransactions[_transactionId];
            return (custodian.unlockTimestamp, custodian.staleTimestamp);
        }
        if (_operationType == 2){
            Token storage token = TokenTransactions[_transactionId];
            return (token.unlockTimestamp, token.staleTimestamp);
        }
        if (_operationType == 3){
            SettlementTransaction storage settlementTransaction = SettlementTransactions[_transactionId];
            return (settlementTransaction.unlockTimestamp, settlementTransaction.staleTimestamp);
        }
        if (_operationType == 4 ){
            ReleaseFunds storage releaseFunds = ReleaseFundsTransactions[_transactionId];
            return (releaseFunds.unlockTimestamp, releaseFunds.staleTimestamp);
        }
        if (_operationType == 5 ){
            QuorumTreshold storage quorumTreshold = QuorumTresholdTransactions[_transactionId];
            return (quorumTreshold.unlockTimestamp, quorumTreshold.staleTimestamp);
        }
        if (_operationType == 6 ){
            Signers storage signers = SignersTransactions[_transactionId];
            return (signers.unlockTimestamp, signers.staleTimestamp);
        }
        require(1==0, "wrong data");
    }

    modifier txNotExecuted(uint _transactionId, uint8 _operation){
        bool valid = false;
        if (_operation == 1){
            valid = CustodianTransactions[_transactionId].executed == false;
        }
        if (_operation == 2){
            valid = TokenTransactions[_transactionId].executed == false;
        }
        if (_operation == 3){
            valid = SettlementTransactions[_transactionId].executed == false;
        }
        if (_operation == 4){
            valid = ReleaseFundsTransactions[_transactionId].executed == false;
        }
        if (_operation == 5){
            valid = QuorumTresholdTransactions[_transactionId].executed == false;
        }
        if (_operation == 6){
            valid = SignersTransactions[_transactionId].executed == false;
        }
        require(valid, "tx already executed");
        _;
    }

    function getOwners() public view returns(address[] memory _owners){
        return (owners);
    }

    function _getTimestamp(uint8 multipler) private view returns (uint timestamp){
        return block.number + multipler*timelock;
    }

    function _checkTimelocks(uint proposedUnlockTime, uint256 _staleTimelock) private view { 
        require (proposedUnlockTime < block.number, "timelock not met");
        require (_staleTimelock > block.number, "transaction staled");
    }

    constructor(address[] memory _owners, uint _requiredSignatures, address _accessControlAddress, address _settlementAddress,
        uint _timelockInDays, uint _staleTransactionInDays)
    {
        require(_owners.length > 0, "not valid owners");
        require(_requiredSignatures > 0 && _requiredSignatures <= _owners.length, "invalid data");
        require(_timelockInDays > 0, "invalid timelock");
        _checkZeroAddress(_accessControlAddress);
        accessControl = AccessControl(_accessControlAddress);
        settlement = Settlement(payable(_settlementAddress));

        for (uint i=0; i< _owners.length; i++){
            _checkZeroAddress(_owners[i]);
            require(!isOwner[_owners[i]], "owner not unique");
            isOwner[_owners[i]] = true;
            owners.push(_owners[i]);
        }

        timelock = AVERAGE_BLOCK_PER_DAY* _timelockInDays;
        STALE_TRANSACTION_BLOCKS = AVERAGE_BLOCK_PER_DAY * _staleTransactionInDays; //transaction goes stale after defined days
        requiredSignatures = _requiredSignatures;
    }

    function submitCustodiansAllowable(address[] calldata _newCustodianAddresses, uint8[] calldata _custodianCategories) public onlyOwner {
        CustodianTransactions.push(Custodian({
            newCustodianAddress: _newCustodianAddresses,
            custodianCategories: _custodianCategories,
            unlockTimestamp: 0,
            staleTimestamp: block.number + STALE_TRANSACTION_BLOCKS,
            executed: false,
            add: true
        }));
        emit NewTransaction(CustodianTransactions.length -1, 1, true);
    }

    function submitTokenAllowed(address _newTokenAddress) public onlyOwner {
        TokenTransactions.push(Token({
            newTokenAddress: _newTokenAddress,
            unlockTimestamp: 0,
            staleTimestamp: block.number + STALE_TRANSACTION_BLOCKS,
            executed: false,
            add: true
        }));
        emit NewTransaction(TokenTransactions.length -1, 2, true);
    }

    function submitTokenRemoved(address _newTokenAddress) public onlyOwner {
        TokenTransactions.push(Token({
            newTokenAddress: _newTokenAddress,
            unlockTimestamp: 0,
            staleTimestamp: block.number + STALE_TRANSACTION_BLOCKS,
            executed: false,
            add: false
        }));
        emit NewTransaction(TokenTransactions.length -1, 2, false);
    }

    function submitSettlementDeletion(uint _settlementUUID) public onlyOwner {
        SettlementTransactions.push(SettlementTransaction({
            settlementUUID: _settlementUUID,
            unlockTimestamp: 0,
            staleTimestamp: block.number + STALE_TRANSACTION_BLOCKS,
            executed: false
        }));
        emit NewTransaction(SettlementTransactions.length -1, 3, true);
    }

    function submitReleaseFunds(address _custodianAddress, address[] memory _tokenAddresses) public onlyOwner{
        _checkZeroAddress(_custodianAddress);
        ReleaseFundsTransactions.push(ReleaseFunds({
            custodianAddress: _custodianAddress,
            unlockTimestamp: 0,
            staleTimestamp: block.number + STALE_TRANSACTION_BLOCKS,
            tokenAddresses: _tokenAddresses,
            executed: false
        }));
        emit NewTransaction(ReleaseFundsTransactions.length -1, 4, true);
    }

    function submitChangeQuorum(bool _add) public onlyOwner{
        QuorumTresholdTransactions.push(QuorumTreshold({
            add:_add,
            unlockTimestamp: 0,
            staleTimestamp: block.number + STALE_TRANSACTION_BLOCKS,
            executed: false
        }));
        emit NewTransaction(QuorumTresholdTransactions.length -1, 5, true);
    }

    function submitSigner(address _signerAddress, bool _add) public onlyOwner{
        _checkZeroAddress(_signerAddress);
        SignersTransactions.push(Signers({
            signer: _signerAddress,
            add:_add,
            unlockTimestamp: 0,
            staleTimestamp: block.number + STALE_TRANSACTION_BLOCKS,
            executed: false
        }));
        emit NewTransaction(SignersTransactions.length -1, 6, true);
    }


    function approveTransaction(uint _transactionId, uint8 _operationType) public 
        onlyOwner() 
        txValid(_transactionId, _operationType)
        txNotExecuted(_transactionId, _operationType) { // 1 for custodian 2 for token 3 for deletion of settlement
        require (!approved[_transactionId][_operationType][msg.], "tx already approved")sender;
        (uint256 unlockTimestamp, uint256 staleTimestamp)  = _getTransactionTimestamps(_transactionId, _operationType);
        require(block.number < staleTimestamp, "tx is stale");
        approved[_transactionId][_operationType][msg.sender] = true;
        if(unlockTimestamp == 0 && _getApprovalCount(_transactionId, _operationType) >= requiredSignatures){
            updateTimeLock(_transactionId, _operationType);
        }
        emit Approved(_transactionId, _operationType);
    }

    function updateTimeLock(uint _transactionId, uint8 _operationType) private {
        if (_operationType == 1){
            Custodian storage custodian = CustodianTransactions[_transactionId];
            custodian.unlockTimestamp = block.number + AVERAGE_BLOCK_PER_DAY;
        }
        if (_operationType == 2){
            Token storage token = TokenTransactions[_transactionId];
            token.unlockTimestamp = _getTimestamp(1);
        }
        if (_operationType == 3){
            SettlementTransaction storage settlementTransaction = SettlementTransactions[_transactionId];
            settlementTransaction.unlockTimestamp = _getTimestamp(1);
        }
        if (_operationType == 4 ){
            ReleaseFunds storage releaseFunds = ReleaseFundsTransactions[_transactionId];
            releaseFunds.unlockTimestamp = _getTimestamp(1); 
        }
        if (_operationType == 5 ){
            QuorumTreshold storage quorumTreshold = QuorumTresholdTransactions[_transactionId];
            quorumTreshold.unlockTimestamp = _getTimestamp(2);
        }
        if (_operationType == 6 ){
            Signers storage signers = SignersTransactions[_transactionId];
            signers.unlockTimestamp = _getTimestamp(2);
        }
    }

    function revokeTransaction(uint _transactionId, uint8 _operationType) public 
        onlyOwner() 
        txValid(_transactionId, _operationType)
        txNotExecuted(_transactionId, _operationType) { 
        require (approved[_transactionId][_operationType][msg.sender], "tx not approved");
        approved[_transactionId][_operationType][msg.sender] = false;
        emit Revoked(_transactionId, _operationType);
    }

    function executeTransaction(uint _transactionId, uint8 _operationType) external
    onlyOwner()
    txValid(_transactionId, _operationType)
    txNotExecuted(_transactionId, _operationType) {
        require(_getApprovalCount(_transactionId, _operationType) >= requiredSignatures, "not enough approvals");
        if (_operationType == 1){
            Custodian storage custodian = CustodianTransactions[_transactionId];
            _checkTimelocks(custodian.unlockTimestamp, custodian.staleTimestamp);
            custodian.executed = true;
            accessControl.setMultipleCustodiansAllowable(custodian.newCustodianAddress, custodian.custodianCategories);
        }
        if (_operationType == 2){
            Token storage token = TokenTransactions[_transactionId];
            _checkTimelocks(token.unlockTimestamp, token.staleTimestamp);
            token.executed = true;
            if (token.add) {
                accessControl.setTokenAllowable(token.newTokenAddress);
            } else {
                accessControl.removeTokenAllowable(token.newTokenAddress);
            }
        }
        if (_operationType == 3){
            SettlementTransaction storage settlementTransaction = SettlementTransactions[_transactionId];
            _checkTimelocks(settlementTransaction.unlockTimestamp, settlementTransaction.staleTimestamp);
            settlementTransaction.executed = true;
            settlement.deleteSettlement(settlementTransaction.settlementUUID);
        }
        if (_operationType == 4 ){
            ReleaseFunds storage releaseFunds = ReleaseFundsTransactions[_transactionId];
            _checkTimelocks(releaseFunds.unlockTimestamp, releaseFunds.staleTimestamp);
            releaseFunds.executed = true;
            settlement.releaseFunds(releaseFunds.custodianAddress, releaseFunds.tokenAddresses);
        }
        if (_operationType == 5 ){
            QuorumTreshold storage quorumTreshold = QuorumTresholdTransactions[_transactionId];
            _checkTimelocks(quorumTreshold.unlockTimestamp, quorumTreshold.staleTimestamp);
            quorumTreshold.executed = true;
            if(quorumTreshold.add) {
                require(owners.length > requiredSignatures, "cannot add more than signers");
                requiredSignatures++;
            }
            else {
                require(requiredSignatures > 1, "quorum need to be higher than 1");
                requiredSignatures--;
            }
        }
        if (_operationType == 6 ){
            Signers storage signers = SignersTransactions[_transactionId];
            _checkTimelocks(signers.unlockTimestamp, signers.staleTimestamp);
            signers.executed = true;
            if(signers.add) {
                require(isOwner[signers.signer] == false, "already a signer");
                owners.push(signers.signer);
                isOwner[signers.signer] = true;
            } else {
                require(isOwner[signers.signer] == true, " not a signer");
                require(owners.length > requiredSignatures, "fewer signers than quorum");
                uint deleteIndex = 0;
                for (uint index = 0; index<owners.length; index++) {
                    if (owners[index] == signers.signer){
                        deleteIndex = index;
                    }
                }
                _deleteOwner(deleteIndex);
                isOwner[signers.signer] = false;
            }
        }
        emit Executed(_transactionId, _operationType);
    }

    function _deleteOwner(uint _index) private {
        for (uint i = _index; i< owners.length -1; i++){
            owners[i] = owners[i+1];
        }
        owners.pop();
    }

    function _getApprovalCount(uint _transactionId, uint8 _operation) private view returns (uint count){
        for (uint i = 0; i < owners.length; i++) {
            if (approved[_transactionId][_operation][owners[i]]){
                count += 1;
            }
        }
        return count;
    }

    function getCustodianData(uint _transactionId) public view returns (address[] memory _custodians, uint8[] memory _category, 
        uint256 _unlockBlock, bool _executed, bool _add){
        Custodian memory data = CustodianTransactions[_transactionId];
        _custodians = data.newCustodianAddress;
        _category = data.custodianCategories;
        _unlockBlock = data.unlockTimestamp;
        _executed = data.executed;
        _add = data.add;    
    }


    function _checkZeroAddress(address _address) internal pure {
        require (_address != address(0), "Invalid address");
    }
}