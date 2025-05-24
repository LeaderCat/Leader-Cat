// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract LEADERCAT is ERC20, ERC20Burnable, Ownable {

    constructor(address _feeRecipient) ERC20("Leader Cat", "LDCT") Ownable(msg.sender) {
        require(_feeRecipient != address(0), "Invalid fee recipient address");
        feeRecipient = _feeRecipient;
        buyFee = 3;  // 3% buy fee
        sellFee = 3; // 3% sell fee
        _mint(msg.sender, 1_000_000_000 * 10**decimals());
    }

    uint256 public constant MAX_FEE_PERCENTAGE = 50;
    uint256 public constant FEE_CHANGE_TIMELOCK = 1 days;

    mapping(address => bool) public isBlacklisted;
    mapping(address => bool) public isDEX;

    address public feeRecipient;
    uint256 public buyFee;
    uint256 public sellFee;
    uint256 public pendingBuyFee;
    uint256 public pendingSellFee;
    uint256 public feeUpdateTimestamp;

    mapping(address => uint256) public unblacklistTimelock;

    event BlacklistUpdated(address indexed account, bool isBlacklisted);
    event FeesUpdated(uint256 buyFee, uint256 sellFee);
    event FeeUpdateQueued(uint256 buyFee, uint256 sellFee);
    event FeeRecipientUpdated(address indexed previousRecipient, address indexed newRecipient);
    event DEXStatusUpdated(address indexed dex, bool status);

    modifier notBlacklisted(address account) {
        require(!isBlacklisted[account], "Address is blacklisted");
        _;
    }


    function transfer(address recipient, uint256 amount)
        public
        override
        notBlacklisted(msg.sender)
        notBlacklisted(recipient)
        returns (bool)
    {
        uint256 netAmount = _applyFees(msg.sender, recipient, amount);
        return super.transfer(recipient, netAmount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    )
        public
        override
        notBlacklisted(sender)
        notBlacklisted(recipient)
        returns (bool)
    {
        uint256 netAmount = _applyFees(sender, recipient, amount);
        return super.transferFrom(sender, recipient, netAmount);
    }

    function _applyFees(
        address sender,
        address recipient,
        uint256 amount
    )
        internal
        returns (uint256)
    {
        uint256 totalFee = 0;
        
        // Calculate buy fee if sender is DEX
        if (isDEX[sender]) {
            totalFee += (amount * buyFee) / 100;
        }
        
        // Calculate sell fee if recipient is DEX
        if (isDEX[recipient]) {
            totalFee += (amount * sellFee) / 100;
        }

        // Ensure total fee doesn't exceed transfer amount
        require(totalFee <= amount, "Fee exceeds transfer amount");

        // Transfer fee if applicable
        if (totalFee > 0) {
            _transfer(sender, feeRecipient, totalFee);
        }

        return amount - totalFee;
    }

    function approve(address spender, uint256 amount)
        public
        virtual
        override
        notBlacklisted(msg.sender)
        notBlacklisted(spender)
        returns (bool)
    {
        return super.approve(spender, amount);
    }

    // function increaseAllowance(address spender, uint256 addedValue)
    //     public
    //     virtual
    //     notBlacklisted(msg.sender)
    //     notBlacklisted(spender)
    //     returns (bool)
    // {
    //     return super.increaseAllowance(spender, addedValue);
    // }

    // function decreaseAllowance(address spender, uint256 subtractedValue)
    //     public
    //     virtual
    //     notBlacklisted(msg.sender)
    //     notBlacklisted(spender)
    //     returns (bool)
    // {
    //     return super.decreaseAllowance(spender, subtractedValue);
    // }

    function burn(uint256 amount) 
        public 
        virtual 
        override 
        notBlacklisted(msg.sender) 
    {
        super.burn(amount);
    }

    function burnFrom(address account, uint256 amount) 
        public 
        virtual 
        override 
        notBlacklisted(msg.sender)
        notBlacklisted(account) 
    {
        super.burnFrom(account, amount);
    }

    function queueFeeUpdate(uint256 _buyFee, uint256 _sellFee) external onlyOwner {
        require(_buyFee <= MAX_FEE_PERCENTAGE, "Buy fee exceeds max limit");
        require(_sellFee <= MAX_FEE_PERCENTAGE, "Sell fee exceeds max limit");
        require(_buyFee + _sellFee <= MAX_FEE_PERCENTAGE, "Total fees exceed max limit");
        
        pendingBuyFee = _buyFee;
        pendingSellFee = _sellFee;
        feeUpdateTimestamp = block.timestamp + FEE_CHANGE_TIMELOCK;
        emit FeeUpdateQueued(_buyFee, _sellFee);
    }

    function executeFeeUpdate() external onlyOwner {
        require(block.timestamp >= feeUpdateTimestamp, "Timelock not expired");
        require(feeUpdateTimestamp != 0, "No fee update queued");
        
        buyFee = pendingBuyFee;
        sellFee = pendingSellFee;
        
        // Reset pending values
        pendingBuyFee = 0;
        pendingSellFee = 0;
        feeUpdateTimestamp = 0;
        
        emit FeesUpdated(buyFee, sellFee);
    }

    function updateBlacklist(address account, bool status) external onlyOwner {
        require(account != address(0), "Invalid address");
        require(account != owner(), "Cannot blacklist owner");
        
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

    function updateFeeRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), "Invalid fee recipient address");
        require(!isBlacklisted[newRecipient], "Fee recipient is blacklisted");
        
        address oldRecipient = feeRecipient;
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(oldRecipient, newRecipient);
    }

    function setDEX(address dex, bool status) external onlyOwner {
        require(dex != address(0), "Invalid DEX address");
        isDEX[dex] = status;
        emit DEXStatusUpdated(dex, status);
    }

    receive() external payable {
        revert("Contract does not accept Ether");
    }

    fallback() external payable {
        revert("Fallback function called: Ether not accepted");
    }
}
