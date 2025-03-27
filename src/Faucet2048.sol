// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Board} from "src/LibBoard.sol";
import {OwnableRoles} from "lib/solady/src/auth/OwnableRoles.sol";
import {SafeTransferLib} from "lib/solady/src/utils/SafeTransferLib.sol";

/**
 * @title  2048 Faucet
 * @author Monad Foundation (github.com/monad-developers)
 * @notice A faucet that releases native tokens on the submission of a winning 2048 game.
 */
contract Faucet2048 is OwnableRoles {
    // =============================================================//
    //                            ERRORS                            //
    // =============================================================//

    /// @dev Emitted when an submitting an empty game.
    error GameEmpty();
    /// @dev Emitted when the trying to play the game when it's paused.
    error GamePaused();
    /// @dev Emitted when an identical solution is replayed.
    error GameReplayed();
    /// @dev Emitted when submitting an uncomitted secret along with the solution.
    error SecretInvalid();
    /// @dev Emitted when submitting a used commitment.
    error CommitmentUsed();
    /// @dev Emitted when submitting a solution with incorrect secret.
    error GameSecretMismatch();
    /// @dev Emitted when the start board position is an invalid 2048 start position.
    error StartBoardInvalid();
    /// @dev Emitted when a board transformation is incorrect.
    error BoardTransformInvalid();
    
    // =============================================================//
    //                            EVENT                             //
    // =============================================================//

    /// @dev Emitted when a new prize-per-win is set.
    event Prize(uint256 prize);
    /// @dev Emitted when a system is paused/unpaused.
    event Paused(bool isPaused);
    /// @dev Emitted when the faucet is funded.
    event Funded(uint256 amount);
    /// @dev Emitted when a new winning solution is successfully processed.
    event NewGameWin(address indexed player);
    /// @dev Emitted when a new commitment is made.
    event NewCommitment(address indexed player, bytes32 value);

    // =============================================================//
    //                          CONSTANTS                           //
    // =============================================================//

    /// @notice Admin role holders can pause/unpause the system and update prize amount per win.
    uint256 public constant ADMIN_ROLE = _ROLE_0;

    /// @dev The four possible moves in 2048.
    uint8 private constant UP = 0;
    uint8 private constant DOWN = 1;
    uint8 private constant LEFT = 2;
    uint8 private constant RIGHT = 3;

    // =============================================================//
    //                           STORAGE                            //
    // =============================================================//
    
    /// @notice Whether the system is paused.
    bool paused;
    
    /// @notice The amount of native token rewarded on submitting a winning solution.
    uint256 public prizePerWin;

    /// @notice Mapping from a commitment value to the player for whom the commitment is reserved.
    mapping (bytes32 commitment => address player) public commitment;

    // =============================================================//
    //                         CONSTRUCTOR                          //
    // =============================================================//

    /// @notice Sets the owner and prize per win for the system.
    constructor(address newOwner, uint256 prize) {
        _setOwner(newOwner);
        prizePerWin = prize;
    }

    // =============================================================//
    //                           RECEIVE                            //
    // =============================================================//

    /// @notice Lets anyone fund the faucet with native tokens.
    receive() external payable {
        emit Funded(msg.value);
    }

    // =============================================================//
    //                           EXTERNAL                           //
    // =============================================================//

    /// @dev Reverts if the system is paused.
    modifier onlyUnpaused() {
        require(!paused, GamePaused());
        _;
    }

    /**
     * @notice Reserves a commitment value for the caller.    
     * @param value The commitment to map to the caller address.
     */
    function commit(bytes32 value) external onlyUnpaused {
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
    function evaluate(bytes calldata game, bytes calldata secret) external onlyUnpaused {
        
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
        require(boards.length > 0, GameEmpty());

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
            SafeTransferLib.safeTransferETH(player, prizePerWin);
        }

        emit NewGameWin(player);
    }

    /// @notice Lets an owner/admin pause or unpause the system.
    function setPause(bool isPaused) external onlyOwnerOrRoles(ADMIN_ROLE) {
        paused = isPaused;
        emit Paused(isPaused);
    }

    /// @notice Lets an owner/admin update the prize per win.
    function setPrizePerWin(uint256 prize) external onlyOwnerOrRoles(ADMIN_ROLE) {
        prizePerWin = prize;
        emit Prize(prizePerWin);
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
    
    /// @dev Validates that the given board is a valid starting position of 2048.
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

    /// @dev Validates that next board is a result of a valid transformation on previous board.
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

    /// @dev Returns whether a board is a winning board.
    function _isWinning(uint256 board) private pure returns (bool) {
        for(uint8 i = 0; i < 16; i += 8) {
            uint256 tile = Board.getTile(board, i);
            if(tile > 10) {
                return true;
            }
        }
        return false;
    }
}