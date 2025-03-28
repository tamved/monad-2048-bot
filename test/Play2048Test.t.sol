// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Play2048} from "src/Play2048.sol";
import {Board} from "src/LibBoard.sol";

contract Play2048Test is Test {
    Play2048 internal game;

    address owner;
    address admin;
    address player;

    event BoardPosition(uint8[16] position);

    function boardBitsToArray(uint256 b) internal pure returns (uint8[16] memory boardArr) {
        for (uint8 i = 0; i < 16; i++) {
            boardArr[i] = uint8((b >> (120 - (i * 8))) & 0xFF);
        }
    }

    function boardArrayToBits(uint8[16] memory b) internal pure returns (uint256) {
        uint256 result = 0;

        for (uint8 i = 0; i < 16; i++) {
            result = (result << 8) | b[i]; // Shift first, then OR
        }

        return result;
    }

    function setUp() public {
        // Setup actors.
        owner = makeAddr("Owner");
        admin = makeAddr("Admin");
        player = makeAddr("Player");

        // Deploy game.
        game = new Play2048(owner);
    }

    // Run with -vvvv to see board positions.
    function testShowcase() public {
        // Start a game and get a starting position.
        bytes32 expectedSessionId = keccak256(abi.encodePacked(player, block.number));
        vm.prank(player);
        game.startGame();

        uint256 startBoard = game.latestBoard(expectedSessionId);
        assertTrue(startBoard > 0);
        assertTrue(Board.validateStartPosition(startBoard));

        emit BoardPosition(boardBitsToArray(startBoard));

        // Play moves.
        vm.startPrank(player);

        game.play(expectedSessionId, Board.RIGHT);
        emit BoardPosition(boardBitsToArray(game.latestBoard(expectedSessionId)));

        game.play(expectedSessionId, Board.UP);
        emit BoardPosition(boardBitsToArray(game.latestBoard(expectedSessionId)));

        game.play(expectedSessionId, Board.LEFT);
        emit BoardPosition(boardBitsToArray(game.latestBoard(expectedSessionId)));

        game.play(expectedSessionId, Board.DOWN);
        emit BoardPosition(boardBitsToArray(game.latestBoard(expectedSessionId)));

        vm.stopPrank();
    }
}
