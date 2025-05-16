// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {StakingPools} from "../src/StakingPools.sol";

contract StakingPoolsScript is Script {
    StakingPools public stakingPools;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // Deploy StakingPools
        stakingPools = new StakingPools();

        vm.stopBroadcast();
    }
}
