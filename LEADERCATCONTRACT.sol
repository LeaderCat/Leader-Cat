// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

contract LEADERCATCONTRACT {
    string public constant name = "TOKEN NAME";
    string public constant symbol = "TOKEN";
    uint256 public constant totalSupply = 1_000_000_000_000 * 10 ** 18;
    uint8 public constant decimals = 18;
    uint256 public constant MAX_FEE_PERCENTAGE = 50;

    mapping(address => uint256) public balanceOf;
    mapping(address => bool) public isBlacklisted;
    mapping(address => bool) public isDEX;

    address public owner;
    address public proposedOwner;
    address public feeRecipient;

    uint256 public buyFee;
    uint256 public sellFee;

    mapping(address => uint256) public unblacklistTimelock;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event BlacklistUpdated(address indexed account, bool isBlacklisted);
    event FeesUpdated(uint256 buyFee, uint256 sellFee);
    event OwnershipProposed(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event FeeRecipientUpdated(address indexed previousRecipient, address indexed newRecipient);

    constructor(address _feeRecipient) {
        require(_feeRecipient != address(0), "Invalid fee recipient address");
        owner = msg.sender;
        feeRecipient = _feeRecipient;
        balanceOf[msg.sender] = totalSupply;
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

    modifier timelockPassedForUnblacklist(address account) {
        require(
            block.timestamp >= unblacklistTimelock[account],
            "Timelock for unblacklist not yet passed"
        );
        _;
    }

    function transfer(address _to, uint256 _amount)
        external
        notBlacklisted(msg.sender)
        notBlacklisted(_to)
        validAddress(_to)
        returns (bool success)
    {
        _transfer(msg.sender, _to, _amount);
        return true;
    }

    function approve(address _spender, uint256 _amount)
        external
        notBlacklisted(msg.sender)
        validAddress(_spender)
        returns (bool success)
    {
        allowance[msg.sender][_spender] = _amount;
        emit Approval(msg.sender, _spender, _amount);
        return true;
    }

    function transferFrom(
        address _from,
        address _to,
        uint256 _amount
    )
        external
        notBlacklisted(_from)
        notBlacklisted(_to)
        validAddress(_to)
        returns (bool success)
    {
        require(allowance[_from][msg.sender] >= _amount, "Allowance exceeded");
        allowance[_from][msg.sender] -= _amount;
        _transfer(_from, _to, _amount);
        return true;
    }

    function _transfer(address _from, address _to, uint256 _amount) internal {
        require(_amount > 0, "Transfer amount must be greater than 0");
        require(balanceOf[_from] >= _amount, "Insufficient balance");

        uint256 fee = 0;

        if (isDEX[_from]) {
            fee = (_amount * buyFee) / 100;
        } else if (isDEX[_to]) {
            fee = (_amount * sellFee) / 100;
        }

        uint256 amountAfterFee = _amount - fee;

        balanceOf[_from] -= _amount;
        balanceOf[_to] += amountAfterFee;

        if (fee > 0) {
            balanceOf[feeRecipient] += fee;
            emit Transfer(_from, feeRecipient, fee);
        }

        emit Transfer(_from, _to, amountAfterFee);
    }

    function updateDEXStatus(address _dexAddress, bool _status) external onlyOwner {
        isDEX[_dexAddress] = _status;
    }
function updateBlacklist(address account, bool status) external onlyOwner {
        if (status) {
            isBlacklisted[account] = true;
            unblacklistTimelock[account] = block.timestamp + 1 days;
        } else {
            require(
                block.timestamp >= unblacklistTimelock[account],
                "Timelock for unblacklist not yet passed"
            );
            isBlacklisted[account] = false;
        }
        emit BlacklistUpdated(account, status);
    }

    function finalizeUnblacklist(address account)
        external
        onlyOwner
        timelockPassedForUnblacklist(account)
    {
        isBlacklisted[account] = false;
        emit BlacklistUpdated(account, false);
    }

    function setFees(uint256 _buyFee, uint256 _sellFee)
        external
        onlyOwner
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
