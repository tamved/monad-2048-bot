// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library Board {
    // =============================================================//
    //                            ERRORS                            //
    // =============================================================//

    error DirtyBits();
    error MoveInvalid();
    error BoardStartInvalid();
    error BoardTransformInvalid();

    // =============================================================//
    //                          CONSTANTS                           //
    // =============================================================//

    uint256 public constant UP = 0;
    uint256 public constant DOWN = 1;
    uint256 public constant LEFT = 2;
    uint256 public constant RIGHT = 3;

    // =============================================================//
    //                            START                             //
    // =============================================================//

    function getStartPosition(bytes32 seed) public pure returns (uint256 position) {
        // Generate pseudo-random seed and get first tile to populate.
        uint256 rseed = uint256(keccak256(abi.encodePacked(seed)));
        uint256 pos1 = rseed % 16;

        // Re-hash seed
        rseed = uint256(keccak256(abi.encodePacked(rseed)));

        // Get second tile to populate.
        uint256 pos2 = rseed % 16;
        while (pos2 == pos1) {
            pos2 = (pos2 + 1) % 16;
        }

        for (uint8 i = 0; i < 16; i++) {
            if (i == pos1 || i == pos2) {
                position = setTile(position, i, (rseed % 100) > 90 ? 2 : 1);
            }
        }
    }

    // =============================================================//
    //                          VALIDATIONS                         //
    // =============================================================//

    function validateStartPosition(uint256 board) public pure returns (bool) {
        require((board>> 128) == 0, DirtyBits());

        uint256 count;
        for (uint8 i = 0; i < 16; i++) {
            // Get value at tile.
            uint8 pow = getTile(board, i);
            // Check: tile value is less than 2^3.
            require(pow < 3, BoardStartInvalid());
            // Update tile count.
            if (pow > 0) count++;
        }
        require(count == 2, BoardStartInvalid());

        return true;
    }

    function validateTransformation(uint256 prevBoard, uint256 nextBoard) public pure returns (bool) {
        require(((prevBoard << 8) >> 136) == 0, DirtyBits());
        require(((nextBoard << 8) >> 136) == 0, DirtyBits());

        uint256 result;
        uint8 move = getMove(nextBoard);

        if (move == UP) {
            result = processMoveUp(prevBoard);
        } else if (move == DOWN) {
            result = processMoveDown(prevBoard);
        } else if (move == RIGHT) {
            result = processMoveRight(prevBoard);
        } else if (move == LEFT) {
            result = processMoveLeft(prevBoard);
        } else {
            revert MoveInvalid();
        }

        uint8 mismatchPosition = 0;
        uint8 mismatchCount = 0;

        for (uint8 i = 0; i < 16; i++) {
            if (getTile(result, i) != getTile(nextBoard, i)) {
                mismatchCount++;
                mismatchPosition = i;
            }
        }
        uint256 mismatchTile = getTile(nextBoard, mismatchPosition);

        require(
            getTile(result, mismatchPosition) == 0 && mismatchTile > 0 && mismatchTile < 3 && mismatchCount == 1,
            BoardTransformInvalid()
        );

        return true;
    }

    // =============================================================//
    //                        TRANSFORMATIONS                       //
    // =============================================================//

    function processMove(uint256 board, uint256 move, bytes32 seed) public pure returns (uint256 result) {
        // Check: the move is valid.
        require(move < 4, MoveInvalid());

        // Perform transformation on board to get resultant
        if (move == UP) {
            result = processMoveUp(board);
        } else if (move == DOWN) {
            result = processMoveDown(board);
        } else if (move == RIGHT) {
            result = processMoveRight(board);
        } else if (move == LEFT) {
            result = processMoveLeft(board);
        }

        // Check: the move is playable.
        require((board << 128) != (result << 128), MoveInvalid());

        uint256 emptySlots = 0;
        for (uint8 i = 0; i < 16; i++) {
            if (getTile(result, i) == 0) {
                emptySlots++;
            }
        }

        if (emptySlots > 0) {
            // Generate pseudo-random seed.
            uint256 rseed = uint256(keccak256(abi.encodePacked(board, move, result, seed)));
            uint8[] memory emptyIndices = new uint8[](emptySlots);
            uint256 idx = 0;
            for (uint8 i = 0; i < 16; i++) {
                if (getTile(result, i) == 0) {
                    emptyIndices[idx] = i;
                    idx++;
                }
            }

            // Set a 2 (90% probability) or a 4 (10% probability) on the randomly chosen tile.
            result = setTile(result, emptyIndices[rseed % emptySlots], (rseed % 100) > 90 ? 2 : 1);
        }

        return (result << 128) >> 128;
    }

    function processMoveUp(uint256 board) public pure returns (uint256 result) {
        for (uint8 col = 0; col < 4; col++) {
            // Extract column
            uint8[4] memory column;
            for (uint8 row = 0; row < 4; row++) {
                column[row] = getTile(board, row * 4 + col);
            }

            // Compress (move non-zero tiles up)
            uint8[4] memory compressedColumn;
            uint8 targetIndex = 0;
            for (uint8 row = 0; row < 4; row++) {
                if (column[row] != 0) {
                    compressedColumn[targetIndex++] = column[row];
                }
            }

            // Merge
            for (uint8 row = 0; row < 3; row++) {
                if (compressedColumn[row] != 0 && compressedColumn[row] == compressedColumn[row + 1]) {
                    compressedColumn[row]++;
                    compressedColumn[row + 1] = 0;
                }
            }

            // Re-compress after merging
            uint8[4] memory finalColumn;
            targetIndex = 0;
            for (uint8 row = 0; row < 4; row++) {
                if (compressedColumn[row] != 0) {
                    finalColumn[targetIndex++] = compressedColumn[row];
                }
            }

            // Update board with transformed column
            for (uint8 row = 0; row < 4; row++) {
                board = setTile(board, row * 4 + col, finalColumn[row]);
            }
        }

        return board;
    }

    function processMoveDown(uint256 board) public pure returns (uint256 result) {
        for (uint8 col = 0; col < 4; col++) {
            // Extract column in reverse order
            uint8[4] memory column;
            for (uint8 row = 0; row < 4; row++) {
                column[row] = getTile(board, row * 4 + col);
            }

            // Reverse the column
            uint8[4] memory reversedColumn;
            for (uint8 row = 0; row < 4; row++) {
                reversedColumn[row] = column[3 - row];
            }

            // Compress (move non-zero tiles up in reversed column)
            uint8[4] memory compressedColumn;
            uint8 targetIndex = 0;
            for (uint8 row = 0; row < 4; row++) {
                if (reversedColumn[row] != 0) {
                    compressedColumn[targetIndex++] = reversedColumn[row];
                }
            }

            // Merge
            for (uint8 row = 0; row < 3; row++) {
                if (compressedColumn[row] != 0 && compressedColumn[row] == compressedColumn[row + 1]) {
                    compressedColumn[row]++;
                    compressedColumn[row + 1] = 0;
                }
            }

            // Re-compress after merging
            uint8[4] memory finalColumn;
            targetIndex = 0;
            for (uint8 row = 0; row < 4; row++) {
                if (compressedColumn[row] != 0) {
                    finalColumn[targetIndex++] = compressedColumn[row];
                }
            }

            // Reverse back to downward direction
            uint8[4] memory downColumn;
            for (uint8 row = 0; row < 4; row++) {
                downColumn[row] = finalColumn[3 - row];
            }

            // Update board with transformed column
            for (uint8 row = 0; row < 4; row++) {
                board = setTile(board, row * 4 + col, downColumn[row]);
            }
        }

        return board;
    }

    function processMoveRight(uint256 board) public pure returns (uint256 result) {
        for (uint8 row = 0; row < 4; row++) {
            // Extract row
            uint8[4] memory rowTiles;
            for (uint8 col = 0; col < 4; col++) {
                rowTiles[col] = getTile(board, row * 4 + col);
            }

            // Reverse the row
            uint8[4] memory reversedRow;
            for (uint8 col = 0; col < 4; col++) {
                reversedRow[col] = rowTiles[3 - col];
            }

            // Compress (move non-zero tiles up in reversed row)
            uint8[4] memory compressedRow;
            uint8 targetIndex = 0;
            for (uint8 col = 0; col < 4; col++) {
                if (reversedRow[col] != 0) {
                    compressedRow[targetIndex++] = reversedRow[col];
                }
            }

            // Merge
            for (uint8 col = 0; col < 3; col++) {
                if (compressedRow[col] != 0 && compressedRow[col] == compressedRow[col + 1]) {
                    compressedRow[col]++;
                    compressedRow[col + 1] = 0;
                }
            }

            // Re-compress after merging
            uint8[4] memory finalRow;
            targetIndex = 0;
            for (uint8 col = 0; col < 4; col++) {
                if (compressedRow[col] != 0) {
                    finalRow[targetIndex++] = compressedRow[col];
                }
            }

            // Reverse back to right direction
            uint8[4] memory rightRow;
            for (uint8 col = 0; col < 4; col++) {
                rightRow[col] = finalRow[3 - col];
            }

            // Update board with transformed row
            for (uint8 col = 0; col < 4; col++) {
                board = setTile(board, row * 4 + col, rightRow[col]);
            }
        }

        return board;
    }

    function processMoveLeft(uint256 board) public pure returns (uint256 result) {
        for (uint8 row = 0; row < 4; row++) {
            // Extract row
            uint8[4] memory rowTiles;
            for (uint8 col = 0; col < 4; col++) {
                rowTiles[col] = getTile(board, row * 4 + col);
            }

            // Compress (move non-zero tiles up)
            uint8[4] memory compressedRow;
            uint8 targetIndex = 0;
            for (uint8 col = 0; col < 4; col++) {
                if (rowTiles[col] != 0) {
                    compressedRow[targetIndex++] = rowTiles[col];
                }
            }

            // Merge
            for (uint8 col = 0; col < 3; col++) {
                if (compressedRow[col] != 0 && compressedRow[col] == compressedRow[col + 1]) {
                    compressedRow[col]++;
                    compressedRow[col + 1] = 0;
                }
            }

            // Re-compress after merging
            uint8[4] memory finalRow;
            targetIndex = 0;
            for (uint8 col = 0; col < 4; col++) {
                if (compressedRow[col] != 0) {
                    finalRow[targetIndex++] = compressedRow[col];
                }
            }

            // Update board with transformed row
            for (uint8 col = 0; col < 4; col++) {
                board = setTile(board, row * 4 + col, finalRow[col]);
            }
        }

        return board;
    }

    function getTile(uint256 board, uint8 pos) public pure returns (uint8) {
        return uint8((board >> ((15 - pos) * 8)) & 0xFF);
    }

    function setTile(uint256 board, uint8 pos, uint8 value) public pure returns (uint256) {
        return (board & ~(0xFF << ((15 - pos) * 8))) | (uint256(value) << ((15 - pos) * 8));
    }

    function getMove(uint256 board) internal pure returns (uint8) {
        return uint8((board >> 248) & 0xFF);
    }
}
