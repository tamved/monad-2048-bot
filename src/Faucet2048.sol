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
    event NewSession(address indexed player, bytes32 indexed id, bytes32 gameHash);
    /// @dev Emitted when a game is started.
    event NewGameStart(address indexed player, bytes32 indexed id, uint256 board);
    /// @dev Emitted when a new valid move is played.
    event NewMove(address indexed player, bytes32 indexed id, uint256 move, uint256 result);

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
     *
     * @param gameHash The hash of the first three moves of the game.
     */
    function createSession(bytes32 sessionId, bytes32 gameHash) external onlyUnpaused updateSeed {
        address player = msg.sender;

        // Check: the game is not being replayed.
        require(gameFor[gameHash] == bytes32(0), GameUsed());

        // Check: provided session is reserved for the player.
        require(sessionFor[sessionId] == address(0), SessionUsed());

        // Map the session to the player.
        sessionFor[sessionId] = player;

        // Reserve the game for the session.
        gameFor[gameHash] = sessionId;

        emit NewSession(player, sessionId, gameHash);
    }

    /**
     * @notice Starts a game for a given session.
     * @dev    The player is expected to send four game boards (start position + 3 moves) encrypted
     *         using a secret, where `hash(secret)` is the sessionId.
     * @param boards An ordered array of game boards after three moves.
     * @param sessionId The unique session id associated with the hash of the provided boards.
     */
    function startGame(bytes32 sessionId, uint256[] calldata boards) external onlyUnpaused updateSeed {
        address player = msg.sender;

        // Check: provided session is reserved for the player.
        require(player == sessionFor[sessionId], SessionInvalid());

        // Check: the game for the session has not started.
        require(latestBoard[sessionId] == 0, GameStarted());

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

    function play(bytes32 sessionId, uint256 move) external onlyUnpaused updateSeed returns (uint256 result) {
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
}
