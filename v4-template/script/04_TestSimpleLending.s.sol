// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import "../src/SimpleLendingTest.sol";

contract TestSimpleLendingScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy test contract with 10 ETH for lending
        SimpleLendingTest testContract = new SimpleLendingTest{value: 10 ether}();
        
        console.log("SimpleLendingTest deployed at:", address(testContract));
        console.log("MockUSDC deployed at:", testContract.getMockUSDCAddress());
        console.log("SimpleLending deployed at:", testContract.getLendingContractAddress());
        
        // Run all tests
        console.log("Running all tests...");
        testContract.runAllTests();
        
        // Get test results
        (uint256 passed, uint256 failed) = testContract.getTestResults();
        console.log("Tests passed:", passed);
        console.log("Tests failed:", failed);
        
        // Show contract balances
        (uint256 ethBalance, uint256 usdcBalance, uint256 lendingEthBalance) = testContract.getContractBalances();
        console.log("Test contract ETH balance:", ethBalance);
        console.log("Test contract USDC balance:", usdcBalance);
        console.log("Lending contract ETH balance:", lendingEthBalance);

        vm.stopBroadcast();
    }
}
