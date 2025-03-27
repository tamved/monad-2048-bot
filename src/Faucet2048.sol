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

    /// @dev Emitted when an identical game has already been played.
    error GameUsed();
    /// @dev Emitted when the trying to play the game when it's paused.
    error GamePaused();
    /// @dev Emitted when an submitting an invalid number of boards to start the game.
    error GameInvalid();
    /// @dev Emitted when starting a game for a session whose game has already started.
    error GameStarted();
    /// @dev Emitted when playing a game for a session whose game has not started.
    error GameNotStarted();
    
    /// @dev Emitted when creating a session with a used session ID.
    error SessionUsed();
    /// @dev Emitted when submitting a game to an invalid session.
    error SessionInvalid();
    
    /// @dev Emitted when the start board position is an invalid 2048 start position.
    error BoardStartInvalid();
    /// @dev Emitted when a board transformation is incorrect.
    error BoardTransformInvalid();

    /// @dev Emitted when a board is encoded incorrectly.
    error DirtyBits();
    /// @dev Emitted when making a move that is invalid.
    error MoveInvalid();
    
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
    event NewGameWin(address indexed player, bytes32 indexed id);
    /// @dev Emitted when a new game session is created.
    event NewSession(address indexed player, bytes32 indexed id);
    /// @dev Emitted when a game is reserved for a session.
    event NewGame(address indexed player, bytes32 indexed id, bytes32 gameHash);
    /// @dev Emitted when a game is started.
    event NewGameStart(address indexed player, bytes32 indexed id, uint256 board);
    /// @dev Emitted when a new valid move is played.
    event NewMove(address indexed player, bytes32 indexed id, uint8 move, uint256 result);

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

    /// @notice Seed used for randomness.
    bytes32 private seed = bytes32("2048");
    
    /// @notice The amount of native token rewarded on submitting a winning solution.
    uint256 public prizePerWin;

    /// @notice Mapping from hash of first 3 moves of a game to the session it is reserved for.
    mapping (bytes32 gameHash => bytes32 sessionId) public gameFor;

    /// @notice Mapping from session to the latest board state.
    mapping (bytes32 sessionId => uint256 board) public latestBoard;
    
    /// @notice Mapping from session ID to the player the session is reserved for.
    mapping (bytes32 sessionId => address player) public sessionFor;

    /// @notice Mapping from sessionId => whether the prize has been distributed for the session.
    mapping (bytes32 sessionId => bool distributed) public prizeDistributed;

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

    /// @dev Updates global seed.
    modifier updateSeed() {
        seed = keccak256(abi.encodePacked(block.number, seed));
        _;
    }

    /// @dev Reverts if the system is paused.
    modifier onlyUnpaused() {
        require(!paused, GamePaused());
        _;
    }

    /**
     * @notice Creates a new game session for a player.
     * @dev    The game session is created for the caller (msg.sender).
     *         The id is meant to be the hash of a secret (used as a xor encryption/decryption key).
     *
     * @param id A unique, unused value treated as the ID for the session.
     */    
    function createSession(bytes32 id) external onlyUnpaused updateSeed {
        // Check: the session ID is unused.
        require(sessionFor[id] == address(0), SessionUsed());

        // Map the session to the player.
        address player = msg.sender;
        sessionFor[id] = player;

        emit NewSession(player, id);
    }

    /**
     * @notice Reserve a game hash (i.e. hash of the first 3 moves of a game) for a session.
     * 
     * @param gameHash The hash of the first three moves of the game.
     * @param sessionId The unique ID of the session.
     */
    function submitGame(bytes32 gameHash, bytes32 sessionId) external onlyUnpaused updateSeed {
        address player = msg.sender;
        
        // Check: provided session is reserved for the player.
        require(player == sessionFor[sessionId], SessionInvalid());

        // Check: the game is not being replayed.
        require(gameFor[gameHash] == bytes32(0), GameUsed());

        // Reserve the game for the session.
        gameFor[gameHash] = sessionId;

        emit NewGame(player, sessionId, gameHash);
    }

    /**
     * @notice Starts a game for a given session.
     * @dev    The player is expected to send four game boards (start position + 3 moves) encrypted
     *         using a secret, where `hash(secret)` is the sessionId.
     * @param encryptedGame An encrypted, ordered array of game boards after three moves.
     * @param secret The encryption/decryption key for the game.
     */
    function startGame(bytes calldata encryptedGame, bytes calldata secret) external onlyUnpaused updateSeed {
        address player = msg.sender;
        bytes32 sessionId = keccak256(abi.encodePacked(secret));

        // Check: provided session is reserved for the player.
        require(player == sessionFor[sessionId], SessionInvalid());

        // Check: the game for the session has not started.
        require(latestBoard[sessionId] == 0, GameStarted());

        // Decrypt game.
        uint256[] memory boards = abi.decode(encryptDecrypt(encryptedGame, secret), (uint256[]));

        // Check: board is exactly 3 moves in.
        require(boards.length == 4, GameInvalid());

        // Check: the game has been reserved for the session.
        bytes32 gameHash = keccak256(abi.encodePacked(boards));
        require(gameFor[gameHash] == sessionId, GameInvalid());

        // Check: the game is a valid game. Assume the boards are ordered.
        for(uint256 i = 0; i < boards.length; i++) {
            if(i == 0) {
                _validateStartPosition(boards[i]);
                continue;
            }
            _validateTransformation(boards[i-1], boards[i]);
        }

        // Store final board.
        latestBoard[sessionId] = boards[boards.length - 1];

        emit NewGameStart(player, sessionId, boards[boards.length - 1]);
    }

    function play(bytes32 sessionId, uint8 move) external onlyUnpaused updateSeed returns (uint256 result) {
        address player = msg.sender;

        // Check: provided session is reserved for the player.
        require(player == sessionFor[sessionId], SessionInvalid());

        // Check: the game for the session has started.
        uint256 board = latestBoard[sessionId];
        require(board > 0, GameNotStarted());

        // Check: the move is valid.
        require(move < 4, MoveInvalid());

        // Perform transformation on board to get resultant board.
        if(move == UP) {
            result = Board.processMoveUp(board);
        } else if (move == DOWN) {
            result = Board.processMoveDown(board);
        } else if (move == RIGHT) {
            result = Board.processMoveRight(board);
        } else if (move == LEFT) {
            result = Board.processMoveLeft(board);
        }

        // Check: the move is playable.
        require((board << 128) != (result << 128), MoveInvalid());

        // Count board empty tiles and whether any tile is winning.
        uint256 emptySlots = 0;
        bool isWinning = false;
        for(uint8 i = 0; i < 16; i++) {
            uint256 tile = Board.getTile(result, i);
            if(tile > 10) {
                isWinning = true;
            }
            if(Board.getTile(result, i) == 0) {
                emptySlots++;
            }    
        }

        // If the game is a winning one:
        if(isWinning && !prizeDistributed[sessionId]) {
            // Distribute prize.
            SafeTransferLib.safeTransferETH(player, prizePerWin);
            // Mark prize as distributed.
            prizeDistributed[sessionId] = true;

            emit NewGameWin(player, sessionId);
        }

        if(emptySlots > 0) {
            // Generate pseudo-random seed.
            uint256 rseed = uint256(keccak256(abi.encodePacked(board, move, result, seed, address(this).balance)));

            // Grab empty tiles indices
            uint8[] memory emptyIndices = new uint8[](emptySlots);
            uint256 idx = 0;
            for(uint8 i = 0; i < 16; i++) {
                if(Board.getTile(result, i) == 0) {
                    emptyIndices[idx] = i;
                    idx++;
                }    
            }

            // Set a 2 (90% probability) or a 4 (10% probability) on the randomly chosen tile.
            result = Board.setTile(result, emptyIndices[rseed % emptySlots], (rseed % 100) > 90 ? 4 : 2);
        }

        // Store updated board.
        latestBoard[sessionId] = result;

        emit NewMove(player, sessionId, move, result);
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
        require(((board << 8) >> 136) == 0, DirtyBits());

        uint256 count;
        for(uint8 i = 0; i < 16; i++) {
            // Get value at tile.
            uint8 pow = Board.getTile(board, i);
            // Check: tile value is less than 2^3. 
            require(pow < 3, BoardStartInvalid());
            // Update tile count.
            if (pow > 0) count++;
        }
        require(count == 2, BoardStartInvalid());
    }

    /// @dev Validates that next board is a result of a valid transformation on previous board.
    function _validateTransformation(uint256 prevBoard, uint256 nextBoard) private pure {
        require(((prevBoard << 8) >> 136) == 0, DirtyBits());
        require(((nextBoard << 8) >> 136) == 0, DirtyBits());

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
}