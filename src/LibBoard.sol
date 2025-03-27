// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library Board {
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
        return uint8((board >> (pos * 8)) & 0xFF);
    }

    function setTile(uint256 board, uint8 pos, uint8 value) public pure returns (uint256) {
        return (board & ~(0xFF << (pos * 8))) | (uint256(value) << (pos * 8));
    }

    function getMove(uint256 board) internal pure returns (uint8) {
        return uint8(board >> 248 & 0xFF);
    }
}
