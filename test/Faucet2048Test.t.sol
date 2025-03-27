// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Faucet2048} from "src/Faucet2048.sol";
import {Board} from "src/LibBoard.sol";

contract Faucet2048Test is Test {

    Faucet2048 internal faucet;

    address owner;
    address admin;
    address player;

    uint256 prizeAmount = 0.1 ether;
    
    function setUp() public {

        owner = makeAddr("Owner");
        admin = makeAddr("Admin");
        player = makeAddr("Player");

        faucet = new Faucet2048(owner, prizeAmount, 4);
    }
}