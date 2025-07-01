// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {StakingPools} from "../src/StakingPools.sol";

contract StakingPoolsScript is Script {
    StakingPools public stakingPools;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        console.log("Deploying StakingPools contract...");
        console.log("Deployer address:", msg.sender);
        console.log("Chain ID:", block.chainid);

        // Deploy StakingPools
        stakingPools = new StakingPools();

        console.log("StakingPools deployed at:", address(stakingPools));
        console.log("Owner:", stakingPools.owner());

        vm.stopBroadcast();

        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("Network: AirDAO Mainnet");
        console.log("Chain ID: 16718");
        console.log("StakingPools Contract:", address(stakingPools));
        console.log("Owner:", stakingPools.owner());
        console.log("=============================");
    }
}
