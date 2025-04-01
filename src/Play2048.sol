// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Board} from "src/LibBoard.sol";
import {OwnableRoles} from "lib/solady/src/auth/OwnableRoles.sol";

/**
 * @title  2048
 * @author Monad Foundation (github.com/monad-developers)
 * @notice Play 2048 onchain!
 */
contract Play2048 is OwnableRoles {
    // =============================================================//
    //                            ERRORS                            //
    // =============================================================//

    /// @dev Emitted when playing a the game that's paused.
    error GamePaused();
    /// @dev Emitted when submitting an invalid game board.
    error GameInvalid();
    /// @dev Emitted when a game hash has already been used.
    error GameHashUsed();
    /// @dev Emitted when playing a game that has not started.
    error GameNotStarted();
    /// @dev Emitted when submitting a game to an invalid session.
    error GameHashInvalid();
    /// @dev Emitted when someone other than the session's player plays the session's game.
    error SessionPlayerInvalid();

    // =============================================================//
    //                            EVENT                             //
    // =============================================================//

    /// @dev Emitted when a system is paused/unpaused.
    event Paused(bool isPaused);
    /// @dev Emitted when a game is committed.
    event NewGameCommitment(address indexed player, bytes32 indexed id, bytes32 game);
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
    //                           STORAGE                            //
    // =============================================================//

    /// @notice Whether the system is paused.
    bool paused;

    /// @notice Mapping from session to the latest board state.
    mapping(bytes32 sessionId => uint256 board) public latestBoard;

    /// @notice Mapping from a hash of first 3 moves to session ID.
    mapping(bytes32 gameHash => bytes32 sessionId) public gameHash;

    /// @notice Mapping from session ID to the player the session is reserved for.
    mapping(bytes32 sessionId => address player) public sessionFor;

    // =============================================================//
    //                         CONSTRUCTOR                          //
    // =============================================================//

    /// @notice Sets the owner and prize per win for the system.
    constructor(address newOwner) {
        _setOwner(newOwner);
    }

    // =============================================================//
    //                             VIEW                             //
    // =============================================================//

    function getBoard(bytes32 sessionId) external view returns (uint8[16] memory boardArr) {
        uint256 b = latestBoard[sessionId];
        for (uint8 i = 0; i < 16; i++) {
            boardArr[i] = Board.getTile(b, i);
        }
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
     * @notice Commits the first 3 moves of a game to a session.
     * 
     * @param game The hash of the game after the first 3 moves.
     */
    function prepareGame(bytes32 sessionId, bytes32 game) external onlyUnpaused {
        // Get player and game session.
        address player = msg.sender;

        // Check: provided session is reserved for the player.
        require(sessionFor[sessionId] == address(0), SessionPlayerInvalid());

        // Check: game not already committed
        require(gameHash[game] == bytes32(0), GameHashUsed());

        // Store session.
        sessionFor[sessionId] = player;

        // Commit game hash to session.
        gameHash[game] = sessionId;

        emit NewGameCommitment(player, sessionId, game);
    }

    /**
     * @notice Starts a new game for a player.
     * 
     * @param sessionId The unique ID of the game.
     * @param game An ordered series of boards.
     */
    function startGame(bytes32 sessionId, uint256[4] calldata game) external onlyUnpaused {
        // Get player.
        address player = msg.sender;

        // Check: provided session is reserved for the player.
        require(player == sessionFor[sessionId], SessionPlayerInvalid());

        // Check: provided game is reserved for session.
        require(gameHash[keccak256(abi.encodePacked(game))] == sessionId, GameHashInvalid());

        // Check: game has valid start board.
        require(Board.validateStartPosition(game[0]), GameInvalid());

        // Check: game has valid board transformations.
        for(uint256 i = 1; i < 4; i++) {
            require(Board.validateTransformation(game[i-1], game[i]), GameInvalid());
        }

        // Store board.
        latestBoard[sessionId] = game[3];

        emit NewGameStart(player, sessionId, game[3]);
    }

    /**
     * @notice Makes a new move in a game.
     * @param sessionId The unique ID of the game.
     */
    function play(bytes32 sessionId, uint256 result) external onlyUnpaused {
        address player = msg.sender;

        // Check: provided session is reserved for the player.
        require(player == sessionFor[sessionId], SessionPlayerInvalid());

        // Check: game has started for session.
        uint256 latest = latestBoard[sessionId];
        require(latest > 0, GameNotStarted());

        // Check: playing a valid move.
        require(Board.validateTransformation(latest, result), GameInvalid());

        // Store updated board.
        latestBoard[sessionId] = result;

        emit NewMove(player, sessionId, Board.getMove(result), result);
    }

    /// @notice Lets an owner/admin pause or unpause the system.
    function setPause(bool isPaused) external onlyOwnerOrRoles(ADMIN_ROLE) {
        paused = isPaused;
        emit Paused(isPaused);
    }
}
