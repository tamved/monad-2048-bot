// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Play2048} from "src/Play2048.sol";
import {Board} from "src/LibBoard.sol";

contract Play2048Test is Test {
    Play2048 internal game;

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
        player = makeAddr("Player");

        // Deploy game.
        game = new Play2048();
    }

    // Run with -vvvv to see board positions.
    function testShowcase() public {

        // Play 3 moves
        uint256 startBoard = Board.getStartPosition(bytes32("random"));

        uint256 board1 = Board.processMove(startBoard, Board.UP, bytes32("random"));
        board1 = board1 | (Board.UP << 248);

        uint256 board2 = Board.processMove(board1, Board.DOWN, bytes32("random"));
        board2 = board2 | (Board.DOWN << 248);

        uint256 board3 = Board.processMove(board2, Board.RIGHT, bytes32("random"));
        board3 = board3 | (Board.RIGHT << 248);

        // Prepare game by commiting the first 3 moves.
        uint256[4] memory boards = [startBoard, board1, board2, board3];
        bytes32 gameHash = keccak256(abi.encodePacked(boards));

        bytes32 sessionId = keccak256(abi.encodePacked(player, block.number));
        vm.prank(player);
        game.prepareGame(sessionId, gameHash);

        assertEq(game.sessionFor(sessionId), player);
        assertEq(game.gameHash(gameHash), sessionId);

        // Start game by revealing commited boards.
        vm.prank(player);
        game.startGame(sessionId, boards);

        assertEq(game.latestBoard(sessionId), board3);

        // Play move.
        uint256 board4 = Board.processMove(board3, Board.LEFT, bytes32("random"));

        // Encode move.
        board4 = board4 | (Board.LEFT << 248);

        /**
         * [0, 0, 1, 0]
         * [0, 0, 0, 0]
         * [0, 0, 0, 1]
         * [0, 0, 0, 0]
         * 
         * UP:
         * [0, 0, 1, 1]
         * [0, 0, 1, 0]
         * [0, 0, 0, 0]
         * [0, 0, 0, 0]
         * 
         * DOWN:
         * [0, 0, 0, 0]
         * [0, 1, 0, 0]
         * [0, 0, 0, 0]
         * [0, 0, 2, 1]
         * 
         * RIGHT:
         * [0, 0, 0, 0]
         * [0, 0, 0, 1]
         * [1, 0, 0, 0]
         * [0, 0, 2, 1]
         * 
         * LEFT:
         * [0, 0, 0, 0]
         * [1, 0, 0, 1]
         * [1, 0, 0, 0]
         * [2, 1, 0, 0]
         */

        // Submit move for validation.
        vm.prank(player);
        game.play(sessionId, board4);

        assertEq(game.latestBoard(sessionId), board4);
    }
}
