// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Board} from "src/LibBoard.sol";
import {SafeTransferLib} from "lib/solady/src/utils/SafeTransferLib.sol";

/**
 * @title  2048 Faucet
 * @author Monad Foundation (github.com/monad-developers)
 * @notice A faucet that releases native tokens on the submission of a winning 2048 game.
 */
contract Faucet2048 {
    // =============================================================//
    //                            ERRORS                            //
    // =============================================================//

    error GameInvalid();
    error GameReplayed();
    error SecretInvalid();    
    error CommitmentUsed();
    error GameSecretMismatch();

    error StartBoardInvalid();
    error BoardTransformInvalid();
    
    
    // =============================================================//
    //                            EVENT                             //
    // =============================================================//

    event NewCommitment(address indexed player, bytes32 value);
    event NewGameWin(address indexed player);

    // =============================================================//
    //                          CONSTANTS                           //
    // =============================================================//

    uint8 private constant UP = 0;
    uint8 private constant DOWN = 1;
    uint8 private constant LEFT = 2;
    uint8 private constant RIGHT = 3;

    // =============================================================//
    //                           STORAGE                            //
    // =============================================================//
    
    uint256 public prizePerWin;

    mapping (bytes32 commitment => address player) public commitment;

    // =============================================================//
    //                           EXTERNAL                           //
    // =============================================================//

    /**
     * @notice Reserves a commitment value for the caller.    
     * @param value The commitment to map to the caller address.
     */
    function commit(bytes32 value) external {
        // Check: the commitment is unused.
        require(commitment[value] == address(0), CommitmentUsed());

        // Map commitment value to caller.
        address player = msg.sender;
        commitment[value] = player;

        emit NewCommitment(player, value);
    }

    /**
     * @notice Evaulates whether a submitted game of 2048 is valid and winning and distributes prize.
     * @param game The encrypted ordered array of board states of a completed 2048 game.
     * @param secret The encryption/decryption key used to decrypt games.
     */
    function evaluate(bytes calldata game, bytes calldata secret) external {
        
        // Check: provided secret is reserved for a player.
        address player = commitment[keccak256(abi.encodePacked(secret))];
        require(player != address(0), SecretInvalid());

        // Check: provided secret and game hash are commited for the same player.
        require(commitment[keccak256(game)] == player, GameSecretMismatch());

        // Check: game is not being replayed.
        bytes32 gameHash = keccak256(bytes.concat(secret, game));
        require(commitment[gameHash] == address(0));

        // Mark the game as played.
        commitment[gameHash] = player;

        // Decrypt game.
        uint256[] memory boards = abi.decode(encryptDecrypt(game, secret), (uint256[]));
        
        // Check: board is not empty.
        require(boards.length > 0, GameInvalid());

        // Check: the game is a valid game. Assume the boards are ordered.
        for(uint256 i = 0; i < boards.length; i++) {
            if(i == 0) {
                _validateStartPosition(boards[i]);
                continue;
            }
            _validateTransformation(boards[i-1], boards[i]);
        }

        // If the game is winning, distribute prize.
        if(_isWinning(boards[boards.length - 1])) {
            _distributePrize(player);
        }

        emit NewGameWin(player);
    }

    // =============================================================//
    //                            PUBLIC                            //
    // =============================================================//

    /**
     *  @notice         Two-way encryption. Encrypt/decrypt data on chain via the same key.
     *  @dev            See: https://ethereum.stackexchange.com/questions/69825/decrypt-message-on-chain
     *                  
     *
     *  @param data     Bytes of data to encrypt/decrypt.
     *  @param key      Secure key used by caller for encryption/decryption.
     *
     *  @return result  Output after encryption/decryption of given data.
     */
    function encryptDecrypt(bytes memory data, bytes calldata key) public pure returns (bytes memory result) {
        // Store data length on stack for later use
        uint256 length = data.length;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            // Set result to free memory pointer
            result := mload(0x40)
            // Increase free memory pointer by lenght + 32
            mstore(0x40, add(add(result, length), 32))
            // Set result length
            mstore(result, length)
        }

        // Iterate over the data stepping by 32 bytes
        for (uint256 i = 0; i < length; i += 32) {
            // Generate hash of the key and offset
            bytes32 hash = keccak256(abi.encodePacked(key, i));

            bytes32 chunk;
            // solhint-disable-next-line no-inline-assembly
            assembly {
                // Read 32-bytes data chunk
                chunk := mload(add(data, add(i, 32)))
            }
            // XOR the chunk with hash
            chunk ^= hash;
            // solhint-disable-next-line no-inline-assembly
            assembly {
                // Write 32-byte encrypted chunk
                mstore(add(result, add(i, 32)), chunk)
            }
        }
    }

    // =============================================================//
    //                           PRIVATE                            //
    // =============================================================//
    
    function _validateStartPosition(uint256 board) private pure {
        uint256 count;
        for(uint8 i = 0; i < 16; i++) {
            // Get value at tile.
            uint8 pow = Board.getTile(board, i);
            // Check: tile value is less than 2^3. 
            require(pow < 3, StartBoardInvalid());
            // Update tile count.
            if (pow > 0) count++;
        }
        require(count == 2, StartBoardInvalid());
    }

    function _validateTransformation(uint256 prevBoard, uint256 nextBoard) private pure {
        uint256 result;
        uint8 move = Board.getMove(nextBoard);

        if(move == UP) {
            result = Board.processMoveUp(prevBoard);
        } else if (move == DOWN) {
            result = Board.processMoveDown(prevBoard);
        } else if (move == RIGHT) {
            result = Board.processMoveRight(prevBoard);
        } else if (move == LEFT) {
            result = Board.processMoveLeft(prevBoard);
        }

        uint8 mismatchPosition = 0;
        uint8 mismatchCount = 0;

        for(uint8 i = 0; i < 16; i++) {
            uint256 tile = Board.getTile(result, i);

            if(tile != Board.getTile(nextBoard, i)) {
                mismatchCount++;
                mismatchPosition = i;
            }
        }

        uint256 mismatchTile = Board.getTile(result, mismatchPosition);
        require(
            Board.getTile(nextBoard, mismatchPosition) == 0
                && mismatchTile > 0
                && mismatchTile < 3
                && mismatchCount == 1,
            BoardTransformInvalid()
        );
    }

    function _isWinning(uint256 board) private pure returns (bool) {
        for(uint8 i = 0; i < 16; i += 8) {
            uint256 tile = Board.getTile(board, i);
            if(tile > 10) {
                return true;
            }
        }
        return false;
    }

    function _distributePrize(address player) private {
        SafeTransferLib.safeTransferETH(player, prizePerWin);
    }
}