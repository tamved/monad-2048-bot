// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "lib/forge-std/src/Test.sol";

library Board {
    // =============================================================//
    //                            ERRORS                            //
    // =============================================================//

    error MoveInvalid();
    error UnexpectedBits();
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
        uint256 pos2 = rseed % 15;
        if (pos2 >= pos1) {
            pos2++;
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
        require((board >> 128) == 0, UnexpectedBits());

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

    function validateTransformation(uint256 prevBoard, uint256 nextBoard, uint256 seed) public pure returns (bool) {
        require(((prevBoard << 8) >> 136) == 0, UnexpectedBits());
        require(((nextBoard << 8) >> 136) == 0, UnexpectedBits());

        uint256 result = processMove(prevBoard, getMove(nextBoard), seed);
        return result == ((nextBoard << 8) >> 8);
    }

    // =============================================================//
    //                        TRANSFORMATIONS                       //
    // =============================================================//

    function processMove(uint256 board, uint256 move, uint256 seed) public pure returns (uint256 result) {
        // Check: the move is valid.
        require(move < 4, MoveInvalid());

        // Perform transformation on board to get resultant
        result = processMove(board, move <= DOWN, move % 2 == 0);

        // Check: the move is playable.
        require((board << 128) != (result << 128), MoveInvalid());

        uint256 slotMask = 0xFF000000000000000000000000000000;

        uint256 emptyIndices;
        uint256 emptySlots;
        uint256 index;

        while (slotMask != 0) {
            if (result & slotMask == 0) {
                emptyIndices |= index << (8 * emptySlots++);
            }
            slotMask >>= 8;
            index++;
        }

        if (emptySlots > 0) {
            // Set a 2 (90% probability) or a 4 (10% probability) on the randomly chosen tile.
            uint8 tile = uint8((emptyIndices >> (8 * (seed % emptySlots))) & 0xFF);
            result = setTile(result, tile, (seed % 100) > 90 ? 2 : 1);
        }

        return (result << 128) >> 128;
    }

    function processMove(uint256 board, bool isVertical, bool isLeft) public pure returns (uint256 result) {
        uint256 shift = 0;
        board &= type(uint128).max;
        uint256 extractMask = isVertical ? 0x000000FF000000FF000000FF000000FF : 0xFFFFFFFF;
        for (uint256 i = 0; i < 4; i++) {
            uint256 compressed = compress(extractMask & board, isVertical, isLeft);
            uint256 merged = merge(compressed, isVertical, isLeft);

            result |= (merged << shift);
            shift += isVertical ? 8 : 32;

            board >>= isVertical ? 8 : 32;
        }
    }

    function compress(uint256 data, bool isVertical, bool isLeft) internal pure returns (uint256 compressed) {
        uint256 shift = isVertical ? 32 : 8;
        uint256 mask = isLeft ? (isVertical ? 0x000000FF000000000000000000000000 : 0xFF000000) : 0xFF;
        uint256 reminderMask = isVertical ? 0x000000FF000000FF000000FF000000FF : 0xFFFFFFFF;
        while (mask != 0 && data != 0) {
            while (data & reminderMask > 0 && data & mask == 0) {
                data = isLeft ? data << shift : data >> shift;
            }
            compressed |= data & mask;
            mask = isLeft ? mask >> shift : mask << shift;
        }
    }

    function merge(uint256 compressed, bool isVertical, bool isLeft) internal pure returns (uint256 merged) {
        uint256 shift = isVertical ? 32 : 8;

        uint256 mask = isLeft ? (isVertical ? 0x000000FF000000000000000000000000 : 0xFF000000) : 0xFF;
        uint256 reminderMask = isVertical ? 0x000000FF000000FF000000FF000000FF : 0xFFFFFFFF;
        uint256 frontMask = isLeft ? mask >> shift : mask << shift;
        uint256 addition = isLeft ? (isVertical ? 0x00000001000000000000000000000000 : 0x01000000) : 0x01;

        while (reminderMask & compressed != 0) {
            uint256 front = isLeft ? (compressed & frontMask) << shift : (compressed & frontMask) >> shift;
            if (compressed & mask == front) {
                compressed = isLeft ? compressed << shift : compressed >> shift;
                compressed += addition;
            }
            merged |= (compressed & mask);

            mask = isLeft ? mask >> shift : mask << shift;
            frontMask = isLeft ? frontMask >> shift : frontMask << shift;
            addition = isLeft ? addition >> shift : addition << shift;
            reminderMask = isLeft ? reminderMask >> shift : reminderMask << shift;
        }
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
