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
    /// @dev Emitted when playing a game that has not started.
    error GameNotStarted();
    /// @dev Emitted when submitting a game to an invalid session.
    error SessionInvalid();

    // =============================================================//
    //                            EVENT                             //
    // =============================================================//

    /// @dev Emitted when a system is paused/unpaused.
    event Paused(bool isPaused);
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

    /// @notice Seed used for randomness.
    bytes32 private seed = bytes32("2048");

    /// @notice Mapping from session to the latest board state.
    mapping(bytes32 sessionId => uint256 board) public latestBoard;

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
     * @notice Starts a new game for a player.
     * @return startBoard The starting position of the game.
     */
    function startGame() external onlyUnpaused updateSeed returns (uint256 startBoard) {
        // Get player and game session.
        address player = msg.sender;
        bytes32 sessionId = keccak256(abi.encodePacked(msg.sender, block.number));

        // Store session.
        sessionFor[sessionId] = player;

        // Get start position.
        startBoard = Board.getStartPosition(seed);

        // Store board.
        latestBoard[sessionId] = startBoard;

        emit NewGameStart(player, sessionId, startBoard);
    }

    /**
     * @notice Makes a new move in a game.
     * @param sessionId The unique ID of the gae.
     * @param move The move to play
     */
    function play(bytes32 sessionId, uint256 move) external onlyUnpaused updateSeed returns (uint256 result) {
        address player = msg.sender;

        // Check: provided session is reserved for the player.
        require(player == sessionFor[sessionId], SessionInvalid());

        // Check: the game for the session has started.
        uint256 board = latestBoard[sessionId];
        require(board > 0, GameNotStarted());

        // Process move.
        result = Board.processMove(board, move, seed);

        // Store updated board.
        latestBoard[sessionId] = result;

        emit NewMove(player, sessionId, move, result);
    }

    /// @notice Lets an owner/admin pause or unpause the system.
    function setPause(bool isPaused) external onlyOwnerOrRoles(ADMIN_ROLE) {
        paused = isPaused;
        emit Paused(isPaused);
    }
}
