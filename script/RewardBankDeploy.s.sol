// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {RewardBank} from "../src/RewardBank.sol";

contract CounterScript is Script {
    RewardBank public rewardBank;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        rewardBank = new RewardBank();

        vm.stopBroadcast();
    }
}
