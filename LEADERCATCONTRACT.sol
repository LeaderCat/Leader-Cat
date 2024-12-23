// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract LEADERCATCONTRACT {
    string public constant name = "TOKEN NAME";
    string public constant symbol = "TOKEN";
    uint256 public constant totalSupply = 1_000_000_000_000_000_000_000_000;
    uint8 public constant decimals = 18;
    uint256 public constant MAX_FEE_PERCENTAGE = 50;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => bool) public isBlacklisted;
    mapping(address => bool) public isDEX;

    address public owner;
    address public proposedOwner;
    address public feeRecipient;

    uint256 public buyFee;
    uint256 public sellFee;

    mapping(bytes4 => uint256) public timelockExpiration;

    bool private _reentrancyLock;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event BlacklistUpdated(address indexed account, bool isBlacklisted);
    event FeesUpdated(uint256 buyFee, uint256 sellFee);
    event OwnershipProposed(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event FeeRecipientUpdated(address indexed previousRecipient, address indexed newRecipient);

    constructor(uint256 _timelockDuration, address _feeRecipient) {
        require(_feeRecipient != address(0), "Invalid fee recipient address");
        owner = msg.sender;
        feeRecipient = _feeRecipient;
        balanceOf[msg.sender] = totalSupply;

        timelockExpiration[this.updateBlacklist.selector] = block.timestamp + _timelockDuration;
        timelockExpiration[this.setFees.selector] = block.timestamp + _timelockDuration;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized: Only owner");
        _;
    }

    modifier notBlacklisted(address account) {
        require(!isBlacklisted[account], "Address is blacklisted");
        _;
    }

    modifier validAddress(address account) {
        require(account != address(0), "Invalid address");
        _;
    }

    modifier timelockPassed(bytes4 selector) {
        require(
            block.timestamp >= timelockExpiration[selector],
            "Timelock in effect"
        );
        _;
        timelockExpiration[selector] = block.timestamp + 1 days;
    }

    modifier noReentrancy() {
        require(!_reentrancyLock, "Reentrancy detected");
        _reentrancyLock = true;
        _;
        _reentrancyLock = false;
    }

    function transfer(address _to, uint256 _amount)
        external
        notBlacklisted(msg.sender)
        notBlacklisted(_to)
        validAddress(_to)
        noReentrancy
        returns (bool success)
    {
        require(_amount > 0, "Transfer amount must be greater than 0");
        require(balanceOf[msg.sender] >= _amount, "Insufficient balance");

        uint256 fee = 0;

        if (isDEX(msg.sender)) {
            // Bu bir satın alma işlemi
            fee = (_amount * buyFee) / MAX_FEE_PERCENTAGE;
        } else if (isDEX(_to)) {
            // Bu bir satış işlemi
            fee = (_amount * sellFee) / MAX_FEE_PERCENTAGE;
        }

        uint256 amountAfterFee = _amount - fee;

        balanceOf[msg.sender] -= _amount;
        balanceOf[_to] += amountAfterFee;

        if (fee > 0) {
            balanceOf[feeRecipient] += fee;
            emit Transfer(msg.sender, feeRecipient, fee);
        }

        emit Transfer(msg.sender, _to, amountAfterFee);
        return true;
    }

    function updateDEXStatus(address _dexAddress, bool _status) external onlyOwner {
        isDEX[_dexAddress] = _status;
    }

    function updateBlacklist(address account, bool status)
        external
        onlyOwner
        timelockPassed(this.updateBlacklist.selector)
    {
        isBlacklisted[account] = status;
        emit BlacklistUpdated(account, status);
    }

function setFees(uint256 _buyFee, uint256 _sellFee)
        external
        onlyOwner
        timelockPassed(this.setFees.selector)
    {
        require(_buyFee > 0 && _sellFee > 0, "Fees must be greater than zero");
        require(_buyFee <= MAX_FEE_PERCENTAGE, "Buy fee exceeds max limit");
        require(_sellFee <= MAX_FEE_PERCENTAGE, "Sell fee exceeds max limit");
        require(_buyFee + _sellFee <= MAX_FEE_PERCENTAGE, "Total fees exceed max limit");

        buyFee = _buyFee;
        sellFee = _sellFee;
        emit FeesUpdated(_buyFee, _sellFee);
    }

    function setFeeRecipient(address _newRecipient) external onlyOwner validAddress(_newRecipient) {
        emit FeeRecipientUpdated(feeRecipient, _newRecipient);
        feeRecipient = _newRecipient;
    }

    function proposeNewOwner(address newOwner) external onlyOwner validAddress(newOwner) {
        proposedOwner = newOwner;
        emit OwnershipProposed(owner, newOwner);
    }

    function acceptOwnership() external {
        require(msg.sender == proposedOwner, "Only proposed owner can accept ownership");
        emit OwnershipTransferred(owner, proposedOwner);
        owner = proposedOwner;
        proposedOwner = address(0);
    }

    receive() external payable {
        revert("Contract does not accept Ether");
    }

    fallback() external payable {
        revert("Fallback function called: Ether not accepted");
    }
}
