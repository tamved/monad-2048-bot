// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

// Base
import { Script } from "lib/forge-std/src/Script.sol";
import { StdUtils } from "lib/forge-std/src/StdUtils.sol";

// Targets
import { Faucet2048 } from "src/Faucet2048.sol";

contract Deploy is StdUtils, Script {
    uint256 internal deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

    // NOTE: set the owner of your choice.
    address owner = address(0);

    function run() public returns (address gameContract) {
        address deployer = vm.addr(deployerPrivateKey);
        if (owner == address(0)) {
            owner = deployer;
        }

        vm.startBroadcast(deployer);
        gameContract = address(new Faucet2048(owner, 0, 11));
        vm.stopBroadcast();
    }
}