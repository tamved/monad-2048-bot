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
    //                          IMMUTABLES                          //
    // =============================================================//

    uint8 public immutable WINNING_POWER;

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
    mapping(bytes32 gameHash => bytes32 sessionId) public gameFor;

    /// @notice Mapping from session to the latest board state.
    mapping(bytes32 sessionId => uint256 board) public latestBoard;

    /// @notice Mapping from session ID to the player the session is reserved for.
    mapping(bytes32 sessionId => address player) public sessionFor;

    /// @notice Mapping from sessionId => whether the prize has been distributed for the session.
    mapping(bytes32 sessionId => bool distributed) public prizeDistributed;

    // =============================================================//
    //                         CONSTRUCTOR                          //
    // =============================================================//

    /// @notice Sets the owner and prize per win for the system.
    constructor(address newOwner, uint256 prize, uint8 winningPower) {
        WINNING_POWER = winningPower;
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
        seed = keccak256(abi.encodePacked(block.number, address(this).balance, seed));
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
        for (uint256 i = 0; i < boards.length; i++) {
            if (i == 0) {
                Board.validateStartPosition(boards[i]);
                continue;
            }
            Board.validateTransformation(boards[i - 1], boards[i]);
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

        // Process move.
        result = Board.processMove(board, move, seed);

        // If the game is a winning one:
        if (Board.isWinningBoard(result, WINNING_POWER) && !prizeDistributed[sessionId]) {
            // Distribute prize.
            SafeTransferLib.safeTransferETH(player, prizePerWin);
            // Mark prize as distributed.
            prizeDistributed[sessionId] = true;

            emit NewGameWin(player, sessionId);
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
}
