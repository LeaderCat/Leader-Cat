// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract LEADERCATCONTRACT is ERC20, ERC20Burnable, Ownable {
    uint256 public constant MAX_FEE_PERCENTAGE = 50;

    mapping(address => bool) public isBlacklisted;
    mapping(address => bool) public isDEX;

    address public feeRecipient;
    uint256 public buyFee;
    uint256 public sellFee;

    mapping(address => uint256) public unblacklistTimelock;

    event BlacklistUpdated(address indexed account, bool isBlacklisted);
    event FeesUpdated(uint256 buyFee, uint256 sellFee);
    event FeeRecipientUpdated(address indexed previousRecipient, address indexed newRecipient);

    modifier notBlacklisted(address account) {
        require(!isBlacklisted[account], "Address is blacklisted");
        _;
    }

    constructor(address _feeRecipient) ERC20("Fixed Token", "FTKN") {
        require(_feeRecipient != address(0), "Invalid fee recipient address");
        feeRecipient = _feeRecipient;
        buyFee = 3;  // 3% buy fee
        sellFee = 3; // 3% sell fee
        _mint(msg.sender, 100_000_000_000 * 10**decimals());
    }

    /**
     * @notice Transfer tokens from `msg.sender` to `recipient`
     *         with potential fee deduction.
     */
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

    /**
     * @notice Transfer tokens from `sender` to `recipient`
     *         via the allowance mechanism, with potential fee deduction.
     */
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

    /**
     * @dev Internal function that calculates and transfers fees if applicable.
     *      Returns the "net amount" that should go to the recipient.
     */
    function _applyFees(
        address sender,
        address recipient,
        uint256 amount
    )
        internal
        returns (uint256)
    {
        uint256 fee;
        // If sender is marked as DEX, apply buyFee
        if (isDEX[sender]) {
            fee = (amount * buyFee) / 100;
        }
        // If recipient is marked as DEX, apply sellFee
        else if (isDEX[recipient]) {
            fee = (amount * sellFee) / 100;
        }

        // Transfer fee to feeRecipient if fee > 0
        if (fee > 0) {
            // This will revert if sender doesn't have enough balance
            _transfer(sender, feeRecipient, fee);
        }

        // Return net amount (amount - fee) for final transfer
        return amount - fee;
    }

    /**
     * @notice Owner can set the buy and sell fees, within defined limits.
     */
    function setFees(uint256 _buyFee, uint256 _sellFee) external onlyOwner {
        require(_buyFee <= MAX_FEE_PERCENTAGE, "Buy fee exceeds max limit");
        require(_sellFee <= MAX_FEE_PERCENTAGE, "Sell fee exceeds max limit");
        require(_buyFee + _sellFee <= MAX_FEE_PERCENTAGE, "Total fees exceed max limit");

        buyFee = _buyFee;
        sellFee = _sellFee;
        emit FeesUpdated(_buyFee, _sellFee);
    }

    /**
     * @notice Owner can blacklist/unblacklist an address.
     *         If blacklisting, it sets a 1-day timelock before unblacklisting is possible.
     */
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

    /**
     * @notice Owner can update the fee recipient.
     */
    function updateFeeRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), "Invalid fee recipient address");
        emit FeeRecipientUpdated(feeRecipient, newRecipient);
        feeRecipient = newRecipient;
    }

    /**
     * @notice Owner can set or unset an address as a DEX.
     */
    function setDEX(address dex, bool status) external onlyOwner {
        isDEX[dex] = status;
    }

    /**
     * @dev Reject all direct ether transfers
     */
    receive() external payable {
        revert("Contract does not accept Ether");
    }

    /**
     * @dev Fallback function also rejects any ether
     */
    fallback() external payable {
        revert("Fallback function called: Ether not accepted");
    }
}
