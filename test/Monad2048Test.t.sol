// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Monad2048} from "src/Monad2048.sol";
import {Board} from "src/LibBoard.sol";

contract Monad2048Test is Test {
    // Target game contract.
    Monad2048 internal game;

    // Game player
    address player;

    function setUp() public {
        // Setup actors.
        player = makeAddr("Player");

        // Deploy game.
        game = new Monad2048();
    }

    function testShowcase() public {
        // Come up with a game ID.
        bytes32 gameId =
            bytes32((uint256(uint160(player)) << 96) + (uint256(keccak256(abi.encodePacked(player, "random"))) >> 160));

        // Play 3 moves.
        uint256 startBoard = Board.getStartPosition(bytes32("random"));

        // The new tile on every move uses the seed `uint256(keccak256(abi.encodePacked(gameId, moveNumber)))` where moveNumber starts at `1`.
        uint256 board1 =
            Board.processMove(startBoard, Board.UP, uint256(keccak256(abi.encodePacked(gameId, uint256(1)))));
        board1 = board1 | (Board.UP << 248);

        uint256 board2 = Board.processMove(board1, Board.DOWN, uint256(keccak256(abi.encodePacked(gameId, uint256(2)))));
        board2 = board2 | (Board.DOWN << 248);

        uint256 board3 =
            Board.processMove(board2, Board.RIGHT, uint256(keccak256(abi.encodePacked(gameId, uint256(3)))));
        board3 = board3 | (Board.RIGHT << 248);

        // Calculate hash of start position plus the first 3 moves.
        uint256[4] memory boards = [startBoard, board1, board2, board3];
        bytes32 gameHash = keccak256(abi.encodePacked(boards));

        assertEq(game.gameHashOf(gameHash), bytes32(0));

        // Start game by revealing commited boards.
        vm.prank(player);
        game.startGame(gameId, boards);

        assertEq(game.gameHashOf(gameHash), gameId);

        assertEq(game.latestBoard(gameId), board3);

        // Play move.
        uint256 board4 = Board.processMove(board3, Board.LEFT, uint256(keccak256(abi.encodePacked(gameId, uint256(4)))));

        // Encode move.
        board4 = board4 | (Board.LEFT << 248);

        // Submit move for validation.
        vm.prank(player);
        game.play(gameId, board4);

        assertEq(game.latestBoard(gameId), board4);
    }
}
