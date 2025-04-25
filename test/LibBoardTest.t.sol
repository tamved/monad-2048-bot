// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Board} from "src/LibBoard.sol";

contract LibBoardTest is Test {
    // Helper function to print values for debugging.
    function boardBitsToArray(uint256 b) internal pure returns (uint8[16] memory boardArr) {
        for (uint8 i = 0; i < 16; i++) {
            boardArr[i] = uint8((b >> (120 - (i * 8))) & 0xFF);
        }
    }

    // Helper function to print values for debugging.
    function boardArrayToBits(uint8[16] memory b) internal pure returns (uint256) {
        uint256 result = 0;

        for (uint8 i = 0; i < 16; i++) {
            result = (result << 8) | b[i]; // Shift first, then OR
        }

        return result;
    }

    function testValidateStartBoard() public {
        /**
         * [0,0,0,0]
         * [0,0,0,0]
         * [0,2,0,0]
         * [0,0,2,0]
         */
        uint8[16] memory goodBoard1 = [0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0];

        /**
         * [0,0,4,0]
         * [0,0,0,0]
         * [0,2,0,0]
         * [0,0,0,0]
         */
        uint8[16] memory goodBoard2 = [0, 0, 2, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0];

        /**
         * [0,0,4,0]
         * [0,0,0,0]
         * [0,4,0,0]
         * [0,0,0,0]
         */
        uint8[16] memory goodBoard3 = [0, 0, 2, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0];

        assertTrue(Board.validateStartPosition(boardArrayToBits(goodBoard1)));
        assertTrue(Board.validateStartPosition(boardArrayToBits(goodBoard2)));
        assertTrue(Board.validateStartPosition(boardArrayToBits(goodBoard3)));

        /**
         * [0,0,2,0]
         * [0,0,0,0]
         * [0,2,0,0]
         * [0,0,2,0]
         */
        uint8[16] memory badBoard1 = [0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0];

        vm.expectRevert(Board.BoardStartInvalid.selector);
        Board.validateStartPosition(boardArrayToBits(badBoard1));

        /**
         * [0,0,0,0]
         * [0,0,0,0]
         * [0,0,0,0]
         * [0,0,0,0]
         */
        uint8[16] memory badBoard2 = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

        vm.expectRevert(Board.BoardStartInvalid.selector);
        Board.validateStartPosition(boardArrayToBits(badBoard2));
    }

    function testValidateTransformation() public pure {
        /**
         * [0,0,1,1]
         * [0,0,2,4]
         * [2,1,3,2]
         * [0,1,3,2]
         */
        uint8[16] memory board = [0, 0, 1, 1, 0, 0, 2, 4, 2, 1, 3, 2, 0, 1, 3, 2];

        /**
         * [0,0,0,0]
         * [0,0,1,1]
         * [0,0,2,4]
         * [2,2,4,3]
         */
        uint8[16] memory expectedResultDown = [0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 2, 4, 2, 2, 4, 3];

        // Populate random tile.
        uint256 seed = uint256(keccak256("random"));
        uint8[] memory emptyIndices = new uint8[](8);
        uint256 idx = 0;
        for (uint8 i = 0; i < 16; i++) {
            if (expectedResultDown[i] == 0) {
                emptyIndices[idx] = i;
                idx++;
            }
        }
        expectedResultDown[emptyIndices[seed % emptyIndices.length]] = (seed % 100) > 90 ? 2 : 1;

        uint256 resultWithMove = boardArrayToBits(expectedResultDown) | (0x01 << 248);

        assertTrue(Board.validateTransformation(boardArrayToBits(board), resultWithMove, seed));
    }

    function testGameOver() public {
        /**
         * [1,2,3,4]
         * [2,3,4,1]
         * [3,4,1,2]
         * [4,1,2,3]
         */
        uint8[16] memory board = [1, 2, 3, 4, 2, 3, 4, 1, 3, 4, 1, 2, 4, 1, 2, 3];

        vm.expectRevert(Board.MoveInvalid.selector);
        Board.processMove(boardArrayToBits(board), Board.UP, uint256(keccak256("random")));

        vm.expectRevert(Board.MoveInvalid.selector);
        Board.processMove(boardArrayToBits(board), Board.DOWN, uint256(keccak256("random")));

        vm.expectRevert(Board.MoveInvalid.selector);
        Board.processMove(boardArrayToBits(board), Board.LEFT, uint256(keccak256("random")));

        vm.expectRevert(Board.MoveInvalid.selector);
        Board.processMove(boardArrayToBits(board), Board.RIGHT, uint256(keccak256("random")));
    }

    function testValidateProcessMovesUpSimple() public pure {
        /**
         * [0,0,0,0]
         * [0,0,2,0]
         * [0,0,2,0]
         * [0,0,0,0]
         */
        uint8[16] memory board1 = [0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0];
        assertTrue(Board.validateStartPosition(boardArrayToBits(board1)));

        // Move: UP
        /**
         * [0,0,4,0]
         * [0,0,0,0]
         * [0,0,0,0]
         * [0,0,0,0]
         */
        uint8[16] memory expectedResultUp = [0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

        // Populate random tile.
        uint256 seed = uint256(keccak256("random"));
        uint8[] memory emptyIndices = new uint8[](15);
        uint256 idx = 0;
        for (uint8 i = 0; i < 16; i++) {
            if (expectedResultUp[i] == 0) {
                emptyIndices[idx] = i;
                idx++;
            }
        }
        expectedResultUp[emptyIndices[seed % emptyIndices.length]] = (seed % 100) > 90 ? 2 : 1;

        uint256 result = Board.processMove(boardArrayToBits(board1), Board.UP, seed);
        assertEq(boardArrayToBits(expectedResultUp), result);
    }

    function testValidateProcessMovesUpComplexMerges() public pure {
        /**
         * [2,4,1,0]
         * [3,2,0,0]
         * [1,2,1,0]
         * [0,0,0,0]
         */
        uint8[16] memory board1 = [2, 4, 1, 0, 3, 2, 0, 0, 1, 2, 1, 0, 0, 0, 0, 0];

        // Move: UP
        /**
         * [2,4,2,0]
         * [3,3,0,0]
         * [1,0,0,0]
         * [0,0,0,0]
         */
        uint8[16] memory expectedResultUp = [2, 4, 2, 0, 3, 3, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0];

        // Populate random tile.
        uint256 seed = uint256(keccak256("random"));
        uint8[] memory emptyIndices = new uint8[](10);
        uint256 idx = 0;
        for (uint8 i = 0; i < 16; i++) {
            if (expectedResultUp[i] == 0) {
                emptyIndices[idx] = i;
                idx++;
            }
        }
        expectedResultUp[emptyIndices[seed % emptyIndices.length]] = (seed % 100) > 90 ? 2 : 1;

        uint256 result = Board.processMove(boardArrayToBits(board1), Board.UP, seed);
        assertEq(boardArrayToBits(expectedResultUp), result);
    }

    function testValidateProcessMovesUpComplexNoMerges() public pure {
        /**
         * [0,0,0,0]
         * [0,0,1,4]
         * [0,0,3,2]
         * [0,1,2,1]
         */
        uint8[16] memory board1 = [0, 0, 0, 0, 0, 0, 1, 4, 0, 0, 3, 2, 0, 1, 2, 1];

        // Move: UP
        /**
         * [0,1,1,4]
         * [0,0,3,2]
         * [0,0,2,1]
         * [0,0,0,0]
         */
        uint8[16] memory expectedResultUp = [0, 1, 1, 4, 0, 0, 3, 2, 0, 0, 2, 1, 0, 0, 0, 0];

        // Populate random tile.
        uint256 seed = uint256(keccak256("random"));
        uint8[] memory emptyIndices = new uint8[](9);
        uint256 idx = 0;
        for (uint8 i = 0; i < 16; i++) {
            if (expectedResultUp[i] == 0) {
                emptyIndices[idx] = i;
                idx++;
            }
        }
        expectedResultUp[emptyIndices[seed % emptyIndices.length]] = (seed % 100) > 90 ? 2 : 1;

        uint256 result = Board.processMove(boardArrayToBits(board1), Board.UP, seed);
        assertEq(boardArrayToBits(expectedResultUp), result);
    }

    function testValidateProcessMovesDownSimple() public pure {
        /**
         * [0,0,0,0]
         * [2,0,0,0]
         * [0,0,2,0]
         * [0,0,0,0]
         */
        uint8[16] memory board1 = [0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0];
        assertTrue(Board.validateStartPosition(boardArrayToBits(board1)));

        // Move: DOWN
        /**
         * [0,0,0,0]
         * [0,0,0,0]
         * [0,0,0,0]
         * [2,0,2,0]
         */
        uint8[16] memory expectedResultDown = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0];

        // Populate random tile.
        uint256 seed = uint256(keccak256("random"));
        uint8[] memory emptyIndices = new uint8[](14);
        uint256 idx = 0;
        for (uint8 i = 0; i < 16; i++) {
            if (expectedResultDown[i] == 0) {
                emptyIndices[idx] = i;
                idx++;
            }
        }
        expectedResultDown[emptyIndices[seed % emptyIndices.length]] = (seed % 100) > 90 ? 2 : 1;

        uint256 result = Board.processMove(boardArrayToBits(board1), Board.DOWN, seed);
        assertEq(boardArrayToBits(expectedResultDown), result);
    }

    function testValidateProcessMovesDownComplexNoMerges() public pure {
        /**
         * [1,1,3,1]
         * [0,2,0,2]
         * [0,0,0,1]
         * [0,0,0,0]
         */
        uint8[16] memory board1 = [1, 1, 3, 1, 0, 2, 0, 2, 0, 0, 0, 1, 0, 0, 0, 0];

        // Move: DOWN
        /**
         * [0,0,0,0]
         * [0,0,0,1]
         * [0,1,0,2]
         * [1,2,3,1]
         */
        uint8[16] memory expectedResultDown = [0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 2, 1, 2, 3, 1];

        // Populate random tile.
        uint256 seed = uint256(keccak256("random"));
        uint8[] memory emptyIndices = new uint8[](9);
        uint256 idx = 0;
        for (uint8 i = 0; i < 16; i++) {
            if (expectedResultDown[i] == 0) {
                emptyIndices[idx] = i;
                idx++;
            }
        }
        expectedResultDown[emptyIndices[seed % emptyIndices.length]] = (seed % 100) > 90 ? 2 : 1;

        uint256 result = Board.processMove(boardArrayToBits(board1), Board.DOWN, seed);
        assertEq(boardArrayToBits(expectedResultDown), result);
    }

    function testValidateProcessMovesDownComplexMerges() public pure {
        /**
         * [0,0,1,1]
         * [0,0,2,4]
         * [2,1,3,2]
         * [0,1,3,2]
         */
        uint8[16] memory board1 = [0, 0, 1, 1, 0, 0, 2, 4, 2, 1, 3, 2, 0, 1, 3, 2];

        // Move: DOWN
        /**
         * [0,0,0,0]
         * [0,0,1,1]
         * [0,0,2,4]
         * [2,2,4,3]
         */
        uint8[16] memory expectedResultDown = [0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 2, 4, 2, 2, 4, 3];

        // Populate random tile.
        uint256 seed = uint256(keccak256("random"));
        uint8[] memory emptyIndices = new uint8[](8);
        uint256 idx = 0;
        for (uint8 i = 0; i < 16; i++) {
            if (expectedResultDown[i] == 0) {
                emptyIndices[idx] = i;
                idx++;
            }
        }
        expectedResultDown[emptyIndices[seed % emptyIndices.length]] = (seed % 100) > 90 ? 2 : 1;

        uint256 result = Board.processMove(boardArrayToBits(board1), Board.DOWN, seed);
        assertEq(boardArrayToBits(expectedResultDown), result);
    }

    function testValidateProcessMovesRightSimple() public pure {
        /**
         * [0,0,0,0]
         * [2,0,0,0]
         * [0,0,2,0]
         * [0,0,0,0]
         */
        uint8[16] memory board1 = [0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0];
        assertTrue(Board.validateStartPosition(boardArrayToBits(board1)));

        // Move: DOWN
        /**
         * [0,0,0,0]
         * [0,0,0,2]
         * [0,0,0,2]
         * [0,0,0,0]
         */
        uint8[16] memory expectedResultRight = [0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0];

        // Populate random tile.
        uint256 seed = uint256(keccak256("random"));
        uint8[] memory emptyIndices = new uint8[](14);
        uint256 idx = 0;
        for (uint8 i = 0; i < 16; i++) {
            if (expectedResultRight[i] == 0) {
                emptyIndices[idx] = i;
                idx++;
            }
        }
        expectedResultRight[emptyIndices[seed % emptyIndices.length]] = (seed % 100) > 90 ? 2 : 1;

        uint256 result = Board.processMove(boardArrayToBits(board1), Board.RIGHT, seed);
        assertEq(boardArrayToBits(expectedResultRight), result);
    }

    function testValidateProcessMovesRightComplexNoMerges() public pure {
        /**
         * [1,2,0,1]
         * [0,1,0,2]
         * [0,0,0,1]
         * [0,3,0,0]
         */
        uint8[16] memory board1 = [1, 2, 0, 1, 0, 1, 0, 2, 0, 0, 0, 1, 0, 3, 0, 0];

        /**
         * [0,1,2,1]
         * [0,0,1,2]
         * [0,0,0,1]
         * [0,0,0,3]
         */
        uint8[16] memory expectedResultRight = [0, 1, 2, 1, 0, 0, 1, 2, 0, 0, 0, 1, 0, 0, 0, 3];

        // Populate random tile.
        uint256 seed = uint256(keccak256("random"));
        uint8[] memory emptyIndices = new uint8[](9);
        uint256 idx = 0;
        for (uint8 i = 0; i < 16; i++) {
            if (expectedResultRight[i] == 0) {
                emptyIndices[idx] = i;
                idx++;
            }
        }
        expectedResultRight[emptyIndices[seed % emptyIndices.length]] = (seed % 100) > 90 ? 2 : 1;

        uint256 result = Board.processMove(boardArrayToBits(board1), Board.RIGHT, seed);
        assertEq(boardArrayToBits(expectedResultRight), result);
    }

    function testValidateProcessMovesRightComplexMerges() public pure {
        /**
         * [1,1,3,1]
         * [0,2,0,2]
         * [0,0,0,1]
         * [0,0,0,0]
         */
        uint8[16] memory board1 = [1, 1, 3, 1, 0, 2, 0, 2, 0, 0, 0, 1, 0, 0, 0, 0];

        /**
         * [0,2,3,1]
         * [0,0,0,3]
         * [0,0,0,1]
         * [0,0,0,0]
         */
        uint8[16] memory expectedResultRight = [0, 2, 3, 1, 0, 0, 0, 3, 0, 0, 0, 1, 0, 0, 0, 0];

        // Populate random tile.
        uint256 seed = uint256(keccak256("random"));
        uint8[] memory emptyIndices = new uint8[](11);
        uint256 idx = 0;
        for (uint8 i = 0; i < 16; i++) {
            if (expectedResultRight[i] == 0) {
                emptyIndices[idx] = i;
                idx++;
            }
        }
        expectedResultRight[emptyIndices[seed % emptyIndices.length]] = (seed % 100) > 90 ? 2 : 1;

        uint256 result = Board.processMove(boardArrayToBits(board1), Board.RIGHT, seed);
        assertEq(boardArrayToBits(expectedResultRight), result);
    }

    function testValidateProcessMovesLeftSimple() public pure {
        /**
         * [0,0,0,0]
         * [2,0,0,0]
         * [0,0,2,0]
         * [0,0,0,0]
         */
        uint8[16] memory board1 = [0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0];
        assertTrue(Board.validateStartPosition(boardArrayToBits(board1)));

        // Move: DOWN
        /**
         * [0,0,0,0]
         * [2,0,0,0]
         * [2,0,0,0]
         * [0,0,0,0]
         */
        uint8[16] memory expectedResultLeft = [0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0];

        // Populate random tile.
        uint256 seed = uint256(keccak256("random"));
        uint8[] memory emptyIndices = new uint8[](14);
        uint256 idx = 0;
        for (uint8 i = 0; i < 16; i++) {
            if (expectedResultLeft[i] == 0) {
                emptyIndices[idx] = i;
                idx++;
            }
        }
        expectedResultLeft[emptyIndices[seed % emptyIndices.length]] = (seed % 100) > 90 ? 2 : 1;

        uint256 result = Board.processMove(boardArrayToBits(board1), Board.LEFT, seed);
        assertEq(boardArrayToBits(expectedResultLeft), result);
    }

    function testValidateProcessMovesLeftComplexNoMerges() public pure {
        /**
         * [1,2,0,1]
         * [0,1,0,2]
         * [0,0,0,1]
         * [0,3,0,0]
         */
        uint8[16] memory board1 = [1, 2, 0, 1, 0, 1, 0, 2, 0, 0, 0, 1, 0, 3, 0, 0];

        /**
         * [1,2,1,0]
         * [1,2,0,0]
         * [1,0,0,0]
         * [3,0,0,0]
         */
        uint8[16] memory expectedResultLeft = [1, 2, 1, 0, 1, 2, 0, 0, 1, 0, 0, 0, 3, 0, 0, 0];

        // Populate random tile.
        uint256 seed = uint256(keccak256("random"));
        uint8[] memory emptyIndices = new uint8[](9);
        uint256 idx = 0;
        for (uint8 i = 0; i < 16; i++) {
            if (expectedResultLeft[i] == 0) {
                emptyIndices[idx] = i;
                idx++;
            }
        }
        expectedResultLeft[emptyIndices[seed % emptyIndices.length]] = (seed % 100) > 90 ? 2 : 1;

        uint256 result = Board.processMove(boardArrayToBits(board1), Board.LEFT, seed);
        assertEq(boardArrayToBits(expectedResultLeft), result);
    }

    function testValidateProcessMovesLeftComplexMerges() public pure {
        /**
         * [1,1,3,1]
         * [0,2,0,2]
         * [0,0,0,1]
         * [0,0,0,0]
         */
        uint8[16] memory board1 = [1, 1, 3, 1, 0, 2, 0, 2, 0, 0, 0, 1, 0, 0, 0, 0];

        /**
         * [2,3,1,0]
         * [3,0,0,0]
         * [1,0,0,0]
         * [0,0,0,0]
         */
        uint8[16] memory expectedResultLeft = [2, 3, 1, 0, 3, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0];

        // Populate random tile.
        uint256 seed = uint256(keccak256("random"));
        uint8[] memory emptyIndices = new uint8[](11);
        uint256 idx = 0;
        for (uint8 i = 0; i < 16; i++) {
            if (expectedResultLeft[i] == 0) {
                emptyIndices[idx] = i;
                idx++;
            }
        }
        expectedResultLeft[emptyIndices[seed % emptyIndices.length]] = (seed % 100) > 90 ? 2 : 1;

        uint256 result = Board.processMove(boardArrayToBits(board1), Board.LEFT, seed);
        assertEq(boardArrayToBits(expectedResultLeft), result);
    }
}
