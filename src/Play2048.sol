// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Board} from "src/LibBoard.sol";
import {OwnableRoles} from "lib/solady/src/auth/OwnableRoles.sol";

/**
 * @title  2048
 * @author Monad Foundation (github.com/monad-developers)
 * @notice Play 2048 onchain!
 */
contract Play2048 {
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
    /// @dev Emitted when submitting a game to an invalid game.
    error GameHashInvalid();
    /// @dev Emitted when someone other than the game's player plays the game's game.
    error GamePlayerInvalid();

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

    /// @dev The four possible moves in 2048.
    uint8 private constant UP = 0;
    uint8 private constant DOWN = 1;
    uint8 private constant LEFT = 2;
    uint8 private constant RIGHT = 3;

    // =============================================================//
    //                           STORAGE                            //
    // =============================================================//

    /// @notice Mapping from game to the latest board state.
    mapping(bytes32 gameId => uint256 board) public latestBoard;

    /// @notice Mapping from a hash of first 3 moves to game ID.
    mapping(bytes32 gameHash => bytes32 gameId) public gameHash;

    /// @notice Mapping from game ID to the player the game is reserved for.
    mapping(bytes32 gameId => address player) public gameFor;

    // =============================================================//
    //                             VIEW                             //
    // =============================================================//

    function getBoard(bytes32 gameId) external view returns (uint8[16] memory boardArr) {
        uint256 b = latestBoard[gameId];
        for (uint8 i = 0; i < 16; i++) {
            boardArr[i] = Board.getTile(b, i);
        }
    }

    // =============================================================//
    //                           EXTERNAL                           //
    // =============================================================//

    /**
     * @notice Commits the first 3 moves of a game to a game.
     * 
     * @param game The hash of the game after the first 3 moves.
     */
    function prepareGame(bytes32 gameId, bytes32 game) external {
        // Get player and game game.
        address player = msg.sender;

        // Check: provided game is reserved for the player.
        require(gameFor[gameId] == address(0), GamePlayerInvalid());

        // Check: game not already committed
        require(gameHash[game] == bytes32(0), GameHashUsed());

        // Store game.
        gameFor[gameId] = player;

        // Commit game hash to game.
        gameHash[game] = gameId;

        emit NewGameCommitment(player, gameId, game);
    }

    /**
     * @notice Starts a new game for a player.
     * 
     * @param gameId The unique ID of the game.
     * @param game An ordered series of boards.
     */
    function startGame(bytes32 gameId, uint256[4] calldata game) external {
        // Get player.
        address player = msg.sender;

        // Check: provided game is reserved for the player.
        require(player == gameFor[gameId], GamePlayerInvalid());

        // Check: provided game is reserved for game.
        require(gameHash[keccak256(abi.encodePacked(game))] == gameId, GameHashInvalid());

        // Check: game has valid start board.
        require(Board.validateStartPosition(game[0]), GameInvalid());

        // Check: game has valid board transformations.
        for(uint256 i = 1; i < 4; i++) {
            require(Board.validateTransformation(game[i-1], game[i]), GameInvalid());
        }

        // Store board.
        latestBoard[gameId] = game[3];

        emit NewGameStart(player, gameId, game[3]);
    }

    /**
     * @notice Makes a new move in a game.
     * @param gameId The unique ID of the game.
     */
    function play(bytes32 gameId, uint256 result) external {
        address player = msg.sender;

        // Check: provided game is reserved for the player.
        require(player == gameFor[gameId], GamePlayerInvalid());

        // Check: game has started for game.
        uint256 latest = latestBoard[gameId];
        require(latest > 0, GameNotStarted());

        // Check: playing a valid move.
        require(Board.validateTransformation(latest, result), GameInvalid());

        // Store updated board.
        latestBoard[gameId] = result;

        emit NewMove(player, gameId, Board.getMove(result), result);
    }
}
