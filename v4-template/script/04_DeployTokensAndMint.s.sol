// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {RealERC20} from "../src/RealERC20.sol";
import {console2} from "forge-std/console2.sol";
/// @notice Deploys two ERC20 tokens and mints them to a specified address
contract DeployTokensAndMintScript is Script {
    // Configuration - Update these as needed
    address constant RECIPIENT_ADDRESS = 0x23178ccD27CDa5D5D18B211aD6648e189c1e16E1; // Replace with actual address
    uint256 constant MINT_AMOUNT = 1000000 * 10**18; // 1 million tokens with 18 decimals
    
    // Token configurations
    string constant TOKEN_A_NAME = "Token A";
    string constant TOKEN_A_SYMBOL = "TKA";
    string constant TOKEN_B_NAME = "Token B";
    string constant TOKEN_B_SYMBOL = "TKB";
    uint8 constant TOKEN_DECIMALS = 18;
    
    function run() public {
        // Get recipient address from environment variable or use default
        address recipient = RECIPIENT_ADDRESS;
        if (vm.envOr("RECIPIENT_ADDRESS", address(0)) != address(0)) {
            recipient = vm.envOr("RECIPIENT_ADDRESS", RECIPIENT_ADDRESS);
        }
        
        // Get mint amount from environment variable or use default
        uint256 mintAmount = MINT_AMOUNT;
        if (vm.envOr("MINT_AMOUNT", uint256(0)) != 0) {
            mintAmount = vm.envOr("MINT_AMOUNT", MINT_AMOUNT);
        }
        
        vm.startBroadcast();
        
        // Deploy Token A
        RealERC20 tokenA = new RealERC20(
            TOKEN_A_NAME,
            TOKEN_A_SYMBOL,
            TOKEN_DECIMALS
        );
        
        // Deploy Token B
        RealERC20 tokenB = new RealERC20(
            TOKEN_B_NAME, 
            TOKEN_B_SYMBOL,
            TOKEN_DECIMALS
        );
        
        // Mint tokens to the recipient address
        tokenA.mint(recipient, mintAmount);
        tokenB.mint(recipient, mintAmount);
        
        vm.stopBroadcast();
        
        // Log the deployed addresses for verification
        console2.log("Token A deployed at:", address(tokenA));
        console2.log("Token B deployed at:", address(tokenB));
        console2.log("Recipient address:", recipient);
        console2.log("Mint amount per token:", mintAmount);
        console2.log("Token A balance:", tokenA.balanceOf(recipient));
        console2.log("Token B balance:", tokenB.balanceOf(recipient));
    }
}
