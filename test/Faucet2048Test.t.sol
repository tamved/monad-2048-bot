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

        // Deploy faucet.
        // Set the winning threshold to 8 (2^3) instead of 2048 (2^11) for tests' sake.
        faucet = new Faucet2048(owner, prizeAmount, 3);

        // Fund the faucet with sufficient prize money.
        vm.deal(address(faucet), 10 ether);
    }

    function testShowcase() public {
        /**
         *  Play game for up till 3 moves.
         *
         *  A 4x4 board position of 2048 is packed in a uint256 as such:
         *      - The rightmost 16 bytes (ordered from left to right) hold
         *        the log_2 of each of the 16 tile value.
         *      - The leftmost 1 byte holds the move type that resulted in
         *        the current board. Starting positions don't contian this.
         *
         */

        /**
         * [0,0,0,0]
         * [2,0,0,0]
         * [0,0,2,0]
         * [0,0,0,0]
         */
        uint8[16] memory board0 = [0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0];
        uint256 board0Bits = boardArrayToBits(board0);

        // Move: DOWN
        /**
         * [0,0,0,2]
         * [0,0,0,0]
         * [0,0,0,0]
         * [2,0,2,0]
         */
        uint8[16] memory board1 = [0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0];
        uint256 board1Bits = boardArrayToBits(board1) | (uint256(Board.DOWN) << 248);

        assertTrue(Board.validateTransformation(board0Bits, board1Bits));

        // Move: LEFT
        /**
         * [2,0,0,0]
         * [0,0,0,0]
         * [0,0,0,4]
         * [4,0,0,0]
         */
        uint8[16] memory board2 = [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 0, 0, 0];
        uint256 board2Bits = boardArrayToBits(board2) | (Board.LEFT << 248);

        // Move: UP
        /**
         * [2,0,0,4]
         * [4,0,0,0]
         * [0,0,0,0]
         * [0,0,2,0]
         */
        uint8[16] memory board3 = [1, 0, 0, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0];
        uint256 board3Bits = boardArrayToBits(board3) | (Board.UP << 248);

        // Setup list of boards and hash them.
        uint256[] memory boards = new uint256[](4);
        boards[0] = board0Bits;
        boards[1] = board1Bits;
        boards[2] = board2Bits;
        boards[3] = board3Bits;

        bytes32 gameHash = keccak256(abi.encodePacked(boards));

        // Create new game session. Commits game start to session.
        bytes32 sessionId = bytes32("random");

        vm.prank(player);
        faucet.createSession(sessionId, gameHash);

        assertEq(faucet.sessionFor(sessionId), player);
        assertEq(faucet.gameFor(gameHash), sessionId);

        // Start the game (reveals game start and enables making moves).
        vm.prank(player);
        faucet.startGame(sessionId, boards);

        assertEq(faucet.latestBoard(sessionId), board3Bits);

        // We now make moves: RIGHT and UP to achieve `8` at the top right corner tile.
        // We have set `8` as the win thresholds for tests. So, we expect the contract
        // to release native token prize to the player.

        assertEq(player.balance, 0);

        vm.startPrank(player);

        faucet.play(sessionId, Board.RIGHT);
        faucet.play(sessionId, Board.UP);

        vm.stopPrank();

        assertEq(player.balance, prizeAmount);
    }
}
