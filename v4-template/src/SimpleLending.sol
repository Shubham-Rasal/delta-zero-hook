// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address owner) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

contract SimpleLending {
    IERC20 public usdc; // PYUSD token (user called it pyusd but example used usdc.transferFrom)
    address public owner;

    uint256 public constant ANNUAL_RATE_BPS = 600; // 6.00% APR in basis points (bps = 1/100 of a %)
    uint256 public constant BPS_DENOM = 10000;
    uint256 public constant YEAR_SECONDS = 365 days;

    struct BorrowPosition {
        uint256 borrowedEth;     // amount of ETH borrowed (in wei)
        uint256 borrowedUsd;     // USD value at borrow time (using borrowPrice)
        uint256 borrowTimestamp; // when borrowed (for interest calculation)
        bool active;
    }

    mapping(address => uint256) public supplied; // PYUSD supplied by user (token units)
    mapping(address => BorrowPosition) public borrows;

    event Deposit(address indexed user, uint256 amount);
    event Borrow(address indexed user, uint256 ethAmountWei, uint256 usdValue);
    event Repay(address indexed user, uint256 paidUsd, uint256 interestUsd);
    event WithdrawSupply(address indexed user, uint256 amount);
    event OwnerWithdrawETH(address indexed to, uint256 amount);
    event OwnerWithdrawERC20(address indexed to, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "only owner");
        _;
    }

    constructor(IERC20 _usdc) {
        usdc = _usdc;
        owner = msg.sender;
    }

    // --- SUPPLY: user deposits PYUSD (usdc) into contract ---
    // user must approve this contract to spend `amount` first using.approve func
    function supply(uint256 amount) external {
        require(amount > 0, "zero amount");
        require(usdc.transferFrom(msg.sender, address(this), amount), "Deposit failed");
        supplied[msg.sender] += amount;
        emit Deposit(msg.sender, amount);
    }

    // Owner can fund contract with ETH to enable lending
    receive() external payable {}
    function repay() external payable {
        delete borrows[msg.sender];
    }

    // --- BORROW ---
    // Uses user's supplied PYUSD as collateral.
    // collateralAssetPrice: USD per PYUSD token (with same decimals as PYUSD assumed; caller must be consistent)
    // borrowAssetPrice: USD per ETH (in same USD units)
    //
    // Algorithm:
    // 1. collateralUsd = supplied[user] * collateralAssetPrice
    // 2. usable = collateralUsd * 90% (10% haircut)
    // 3. ethToSend = usable / borrowAssetPrice
    // 4. transfer ethToSend (in wei) to borrower, save position
    //
    // NOTE: Prices must be provided in consistent units. This simple implementation expects
    // the caller to pass prices scaled appropriately — in production use an oracle.
    function borrow(
        uint256 collateralAssetPrice, // USD per PYUSD (scaled by same token decimals)
        uint256 borrowAssetPrice      // USD per ETH (scaled to the same USD units)
    ) external {
        // require(supplied[msg.sender] > 0, "no collateral supplied");
        // require(!borrows[msg.sender].active, "existing borrow active");

        // Compute collateral USD value (simple multiplication). Caller must ensure consistent scaling.
        // For example: if PYUSD has 18 decimals and price is with 18-decimal scale, the math is consistent.
        uint256 collateralAmount = usdc.balanceOf(address(this));
        collateralAmount = collateralAmount / 10 ** (6);


        // collateralUsd = collateralAmount * collateralAssetPrice
        // To avoid overflow, do the multiplication in 256-bit; caller must choose scales reasonably.
        uint256 collateralUsd = collateralAmount * collateralAssetPrice;

        // Apply 10% haircut -> usable = 90% of collateralUsd
        uint256 usableUsd = (collateralUsd * 90) / 100;

        require(usableUsd > 0, "usable collateral zero");

        // Compute ETH amount to send: ethToSend = usableUsd / borrowAssetPrice
        // To preserve fractional wei, compute with a scaling factor. We'll assume borrowAssetPrice uses same USD scaling.
        // ethToSendWei = usableUsd * 1e18 / borrowAssetPrice;
        // To avoid assuming token decimals, we treat borrowAssetPrice as USD * 1 (user-provided). The caller must be consistent.
        // Here we compute safe: ethWei = usableUsd * 1e18 / borrowAssetPrice
        uint256 ethToSend = (usableUsd * 1 ether) / borrowAssetPrice;

        require(ethToSend > 0, "eth to send zero");
        require(address(this).balance >= ethToSend, "contract has insufficient ETH liquidity");

        // Record borrow position
        borrows[msg.sender] = BorrowPosition({
            borrowedEth: ethToSend,
            borrowedUsd: usableUsd,   // USD principal (we store the USD value used)
            borrowTimestamp: block.timestamp,
            active: true
        });

        // Transfer ETH
        (bool sent, ) = payable(msg.sender).call{value: ethToSend}("");
        require(sent, "ETH transfer failed");

        emit Borrow(msg.sender, ethToSend, usableUsd);
    }

    // --- REPAY ---
    // User repays the outstanding USD value (in PYUSD tokens) plus interest accrued at 6% APR.
    // User must approve the contract to spend the repay amount.
    function repayWithERC20() external {
        BorrowPosition storage pos = borrows[msg.sender];
        require(pos.active, "no active borrow");

        // Compute elapsed time and interest
        uint256 elapsed = block.timestamp - pos.borrowTimestamp;
        // interestUsd = borrowedUsd * ANNUAL_RATE_BPS / BPS_DENOM * elapsed / YEAR_SECONDS
        // Reorder to avoid precision loss:
        // interestUsd = borrowedUsd * ANNUAL_RATE_BPS * elapsed / (BPS_DENOM * YEAR_SECONDS)
        uint256 interestUsd = (pos.borrowedUsd * ANNUAL_RATE_BPS * elapsed) / (BPS_DENOM * YEAR_SECONDS);

        uint256 totalOwedUsd = pos.borrowedUsd + interestUsd;

        // The repay is made in PYUSD tokens (usdc). Caller must use compatible scaling.
        require(usdc.transferFrom(msg.sender, address(this), totalOwedUsd), "Repay transfer failed");

        // Clear borrow position
        emit Repay(msg.sender, pos.borrowedUsd, interestUsd);
        delete borrows[msg.sender];

        // Note: supplied collateral remains in contract under supplied[msg.sender].
        // Optionally, you might want to reduce supplied or automatically release collateral.
    }

    // --- Optional: allow user to withdraw their supplied PYUSD if they have no active borrow ---
    function withdrawSupply(uint256 amount) external {
        require(amount > 0, "zero amount");
        require(supplied[msg.sender] >= amount, "insufficient supplied");
        require(!borrows[msg.sender].active, "active borrow, can't withdraw");

        supplied[msg.sender] -= amount;
        require(usdc.transfer(msg.sender, amount), "withdraw transfer failed");
        emit WithdrawSupply(msg.sender, amount);
    }

    // Owner functions for cleaning up / withdrawing tokens that have collected in contract
    function ownerWithdrawETH(uint256 amountWei, address payable to) external onlyOwner {
        require(address(this).balance >= amountWei, "insufficient ETH");
        (bool sent, ) = to.call{value: amountWei}("");
        require(sent, "eth withdraw failed");
        emit OwnerWithdrawETH(to, amountWei);
    }

    function ownerWithdrawERC20(uint256 amount, address to) external onlyOwner {
        require(usdc.transfer(to, amount), "token withdraw failed");
        emit OwnerWithdrawERC20(to, amount);
    }

    // --- Views ---
    function getBorrowPosition(address user) external view returns (BorrowPosition memory) {
        return borrows[user];
    }
}