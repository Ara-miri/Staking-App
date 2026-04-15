//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {SRTToken} from "../src/SRTToken.sol";
import {Staking} from "../src/Staking.sol";

contract DeployScript is Script {
    uint256 constant REWARD_RATE = 10;
    uint256 constant LOCK_PERIOD = 6 hours;
    uint256 constant TOKEN_SUPPLY = 1_000_000 ether;
    uint256 constant REWARD_POOL = 100_000 ether;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        console.log("Deployer :", deployer);
        console.log("Balance  :", deployer.balance / 1e18, "BNB");

        vm.startBroadcast(pk);

        SRTToken token = new SRTToken(TOKEN_SUPPLY);
        console.log("SRTToken :", address(token));

        Staking staking = new Staking(address(token), REWARD_RATE, LOCK_PERIOD);
        console.log("Staking  :", address(staking));

        token.approve(address(staking), REWARD_POOL);
        staking.fundRewardPool(REWARD_POOL);
        console.log("Reward pool funded with", REWARD_POOL / 1e18, "tokens");

        vm.stopBroadcast();

        console.log("\n--- Copy into frontend/js/config.js ---");
        console.log("TOKEN_ADDRESS  =", address(token));
        console.log("STAKING_ADDRESS=", address(staking));
    }
}
