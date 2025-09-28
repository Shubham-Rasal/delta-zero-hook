// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./SimpleLending.sol";

// Mock USDC/PYUSD token for testing
contract MockUSDC {
    string public name = "Mock USDC";
    string public symbol = "mUSDC";
    uint8 public decimals = 6;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    constructor() {
        // Mint 1M USDC to deployer for testing
        balanceOf[msg.sender] = 1_000_000 * 10**decimals;
    }
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        
        emit Transfer(from, to, amount);
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
}

contract SimpleLendingTest {
    SimpleLending public lendingContract;
    MockUSDC public mockUSDC;
    
    // Test state tracking
    uint256 public testsPassed;
    uint256 public testsFailed;
    
    // Events for test results
    event TestResult(string testName, bool passed, string reason);
    event TestSummary(uint256 passed, uint256 failed);
    
    constructor() payable {
        // Deploy mock USDC
        mockUSDC = new MockUSDC();
        
        // Deploy SimpleLending with mock USDC
        lendingContract = new SimpleLending(IERC20(address(mockUSDC)));
        
        // Fund the lending contract with ETH for lending
        (bool sent, ) = payable(address(lendingContract)).call{value: msg.value}("");
        require(sent, "Failed to fund lending contract");
        
        // Mint some USDC to this test contract for testing
        mockUSDC.mint(address(this), 10000 * 10**6); // 10,000 USDC
    }
    
    // Allow contract to receive ETH
    receive() external payable {}
    
    // Test basic borrow functionality
    function testBorrow() public {
        string memory testName = "testBorrow";
        
        try this._testBorrowInternal() {
            testsPassed++;
            emit TestResult(testName, true, "Borrow test passed");
        } catch Error(string memory reason) {
            testsFailed++;
            emit TestResult(testName, false, reason);
        } catch {
            testsFailed++;
            emit TestResult(testName, false, "Unknown error in borrow test");
        }
    }
    
    function _testBorrowInternal() external {
        // Setup: Supply collateral to lending contract
        uint256 collateralAmount = 1000 * 10**6; // 1000 USDC
        mockUSDC.approve(address(lendingContract), collateralAmount);
        lendingContract.supply(collateralAmount);
        
        // Record initial ETH balance
        uint256 initialBalance = address(this).balance;
        
        // Test borrow with realistic prices
        // Assume USDC = $1, ETH = $2000
        uint256 collateralPrice = 1 * 10**18; // $1 per USDC (18 decimals for consistency)
        uint256 borrowPrice = 2000 * 10**18;  // $2000 per ETH
        
        // Call borrow
        lendingContract.borrow(collateralPrice, borrowPrice);
        
        // Verify we received ETH
        uint256 finalBalance = address(this).balance;
        require(finalBalance > initialBalance, "No ETH received from borrow");
        
        // Verify borrow position was created
        SimpleLending.BorrowPosition memory position = lendingContract.getBorrowPosition(address(this));
        require(position.active, "Borrow position not active");
        require(position.borrowedEth > 0, "No ETH borrowed");
    }
    
    // Test ETH repay functionality
    function testRepayETH() public {
        string memory testName = "testRepayETH";
        
        try this._testRepayETHInternal() {
            testsPassed++;
            emit TestResult(testName, true, "ETH repay test passed");
        } catch Error(string memory reason) {
            testsFailed++;
            emit TestResult(testName, false, reason);
        } catch {
            testsFailed++;
            emit TestResult(testName, false, "Unknown error in ETH repay test");
        }
    }
    
    function _testRepayETHInternal() external {
        // First, create a borrow position
        uint256 collateralAmount = 1000 * 10**6; // 1000 USDC
        mockUSDC.approve(address(lendingContract), collateralAmount);
        lendingContract.supply(collateralAmount);
        
        uint256 collateralPrice = 1 * 10**18; // $1 per USDC
        uint256 borrowPrice = 2000 * 10**18;  // $2000 per ETH
        
        lendingContract.borrow(collateralPrice, borrowPrice);
        
        // Verify borrow position exists
        SimpleLending.BorrowPosition memory positionBefore = lendingContract.getBorrowPosition(address(this));
        require(positionBefore.active, "No active borrow position");
        
        // Repay with ETH (the simple repay function just deletes the position)
        lendingContract.repay{value: 0.1 ether}();
        
        // Verify position was cleared
        SimpleLending.BorrowPosition memory positionAfter = lendingContract.getBorrowPosition(address(this));
        require(!positionAfter.active, "Borrow position still active after repay");
    }
    
    // Test ERC20 repay functionality
    function testRepayERC20() public {
        string memory testName = "testRepayERC20";
        
        try this._testRepayERC20Internal() {
            testsPassed++;
            emit TestResult(testName, true, "ERC20 repay test passed");
        } catch Error(string memory reason) {
            testsFailed++;
            emit TestResult(testName, false, reason);
        } catch {
            testsFailed++;
            emit TestResult(testName, false, "Unknown error in ERC20 repay test");
        }
    }
    
    function _testRepayERC20Internal() external {
        // First, create a borrow position
        uint256 collateralAmount = 1000 * 10**6; // 1000 USDC
        mockUSDC.approve(address(lendingContract), collateralAmount);
        lendingContract.supply(collateralAmount);
        
        uint256 collateralPrice = 1 * 10**18; // $1 per USDC
        uint256 borrowPrice = 2000 * 10**18;  // $2000 per ETH
        
        lendingContract.borrow(collateralPrice, borrowPrice);
        
        // Get borrow position details
        SimpleLending.BorrowPosition memory position = lendingContract.getBorrowPosition(address(this));
        require(position.active, "No active borrow position");
        
        // Wait a bit for interest to accrue (simulate time passage)
        // In a real test, you'd use vm.warp() or similar
        
        // Calculate repay amount (principal + interest)
        // For simplicity, we'll approve a bit more than borrowed USD value
        uint256 repayAmount = position.borrowedUsd + (position.borrowedUsd * 10 / 100); // Add 10% buffer
        
        // Approve and repay with ERC20
        mockUSDC.approve(address(lendingContract), repayAmount);
        lendingContract.repayWithERC20();
        
        // Verify position was cleared
        SimpleLending.BorrowPosition memory positionAfter = lendingContract.getBorrowPosition(address(this));
        require(!positionAfter.active, "Borrow position still active after ERC20 repay");
    }
    
    // Test edge cases
    function testBorrowWithoutCollateral() public {
        string memory testName = "testBorrowWithoutCollateral";
        
        try this._testBorrowWithoutCollateralInternal() {
            testsFailed++;
            emit TestResult(testName, false, "Should have failed but didn't");
        } catch {
            testsPassed++;
            emit TestResult(testName, true, "Correctly failed when borrowing without collateral");
        }
    }
    
    function _testBorrowWithoutCollateralInternal() external {
        // Try to borrow without supplying collateral
        uint256 collateralPrice = 1 * 10**18;
        uint256 borrowPrice = 2000 * 10**18;
        
        lendingContract.borrow(collateralPrice, borrowPrice);
    }
    
    // Run all tests
    function runAllTests() external {
        testBorrow();
        testRepayETH();
        testRepayERC20();
        testBorrowWithoutCollateral();
        
        emit TestSummary(testsPassed, testsFailed);
    }
    
    // Helper functions for integration with Counter.sol
    function simulateBorrowForCounter(
        uint256 collateralAssetPrice,
        uint256 borrowAssetPrice
    ) external returns (bool success) {
        try lendingContract.borrow(collateralAssetPrice, borrowAssetPrice) {
            return true;
        } catch {
            return false;
        }
    }
    
    function simulateRepayForCounter() external payable returns (bool success) {
        try lendingContract.repay{value: msg.value}() {
            return true;
        } catch {
            return false;
        }
    }
    
    // View functions
    function getTestResults() external view returns (uint256 passed, uint256 failed) {
        return (testsPassed, testsFailed);
    }
    
    function getLendingContractAddress() external view returns (address) {
        return address(lendingContract);
    }
    
    function getMockUSDCAddress() external view returns (address) {
        return address(mockUSDC);
    }
    
    function getContractBalances() external view returns (
        uint256 ethBalance,
        uint256 usdcBalance,
        uint256 lendingContractEthBalance
    ) {
        return (
            address(this).balance,
            mockUSDC.balanceOf(address(this)),
            address(lendingContract).balance
        );
    }
}
