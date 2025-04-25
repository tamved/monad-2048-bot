// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Board} from "src/LibBoard.sol";

/**
 * @title  Monad 2048
 * @author Monad Foundation (github.com/monad-developers)
 * @notice Play 2048 onchain! Also read: https://blog.monad.xyz
 */
contract Monad2048 {
    // =============================================================//
    //                            ERRORS                            //
    // =============================================================//

    /// @dev Emitted when starting a game with a used ID.
    error GameIdUsed();
    /// @dev Emitted when starting a game that has already been played.
    error GamePlayed();
    /// @dev Emitted when submitting an invalid game board.
    error GameBoardInvalid();
    /// @dev Emitted when someone other than a game's player makes a move.
    error GamePlayerInvalid();

    // =============================================================//
    //                            EVENT                             //
    // =============================================================//

    /// @dev Emitted when a game is started.
    event NewGame(address indexed player, bytes32 indexed id, uint256 board);
    /// @dev Emitted when a new valid move is played.
    event NewMove(address indexed player, bytes32 indexed id, uint256 move, uint256 result);

    // =============================================================//
    //                           STORAGE                            //
    // =============================================================//

    /// @notice Mapping from game ID to the player.
    mapping(bytes32 gameId => address player) public gameFor;
    /// @notice Mapping from game ID to the latest board state.
    mapping(bytes32 gameId => uint256 board) public latestBoard;
    /// @notice Mapping from game ID to the move count of the game.
    mapping(bytes32 gameId => uint256 nextMove) public nextMove;
    /// @notice Mapping from a hash of start position plus first 3 moves to game ID.
    mapping(bytes32 gameHash => bytes32 gameId) public gameHashOf;

    // =============================================================//
    //                             VIEW                             //
    // =============================================================//

    /**
     * @notice Returns the latest board position of a game.
     * @dev Each array position stores the log_2 of that tile's value.
     * @param gameId The unique ID of a game.
     */
    function getBoard(bytes32 gameId) external view returns (uint8[16] memory boardArr, uint256 nextMoveNumber) {
        uint256 b = latestBoard[gameId];
        for (uint8 i = 0; i < 16; i++) {
            boardArr[i] = Board.getTile(b, i);
        }
        nextMoveNumber = nextMove[gameId];
    }

    // =============================================================//
    //                           EXTERNAL                           //
    // =============================================================//

    /**
     * @notice Starts a new game for a player.
     *
     * @param gameId The unique ID of the game.
     * @param boards An ordered series of a start board and the result boards
     *               of the first three moves.
     */
    function startGame(bytes32 gameId, uint256[4] calldata boards) external {
        // Get player.
        address player = msg.sender;

        // Check: provided game ID is unused.
        require(gameFor[gameId] == address(0), GameIdUsed());

        // Check: this exact sequence of boards has not been played.
        bytes32 hashedBoards = keccak256(abi.encodePacked(boards));
        require(gameHashOf[hashedBoards] == bytes32(0), GamePlayed());

        // Check: game has a valid start board.
        require(Board.validateStartPosition(boards[0]), GameBoardInvalid());

        // Check: game has valid board transformations.
        for (uint256 i = 1; i < 4; i++) {
            require(
                Board.validateTransformation(boards[i - 1], boards[i], uint256(keccak256(abi.encodePacked(gameId, i)))),
                GameBoardInvalid()
            );
        }

        // Reserve game for player.
        gameFor[gameId] = player;

        // Store seed for game.
        nextMove[gameId] = 4;

        // Mark the game-start as played.
        gameHashOf[hashedBoards] = gameId;

        // Store the latest board of the game.
        latestBoard[gameId] = boards[3];

        emit NewGame(player, gameId, boards[3]);
    }

    /**
     * @notice Makes a new move in a game.
     * @param gameId The unique ID of the game.
     * @param resultBoard The result of applying a move on the latest board.
     */
    function play(bytes32 gameId, uint256 resultBoard) external {
        // Get player.
        address player = msg.sender;

        // Check: provided game is reserved for the player.
        require(player == gameFor[gameId], GamePlayerInvalid());

        // Check: playing a valid move.
        require(
            Board.validateTransformation(
                latestBoard[gameId], resultBoard, uint256(keccak256(abi.encodePacked(gameId, nextMove[gameId])))
            ),
            GameBoardInvalid()
        );

        // Update board.
        latestBoard[gameId] = resultBoard;

        // Update move count.
        nextMove[gameId]++;

        emit NewMove(player, gameId, Board.getMove(resultBoard), resultBoard);
    }
}
