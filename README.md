# 2048 Bot for Monad Blockchain Stress Testing


An automated bot that plays 2048 at high speed while generating blockchain transactions on [Monad's 2048 implementation](https://github.com/monad-developers/2048-contracts). Designed for stress testing the Monad blockchain through continuous game interactions.

## Features

- 🚀 **High-speed gameplay** with 50ms move interval
- 🧠 **AI-powered moves** using Expectimax algorithm with:
  - Transposition table for memoization
  - Configurable search depth (default: 5)
  - Sophisticated board evaluation heuristics
- ⛓️ **Automatic transaction generation** with each move
- ⚙️ Customizable weights for board evaluation metrics
- 📊 Real-time move statistics and error handling

## Installation

1. Navigate to [2048.monad.xyz](https://2048.monad.xyz/)
2. Open browser developer console (F12)
3. Paste the entire contents of `bot.js` into the console and press Enter

## Usage

The bot starts automatically after injection. Console commands:
```javascript
// Pause the bot
isRunning = false;

// Resume the bot
isRunning = true;

// Reset move counter
moveCount = 0;
```

Configuration (Edit in bot.js)

```javascript
const MOVE_INTERVAL = 50;    // Time between moves (ms)
const SEARCH_DEPTH = 5;      // AI lookahead depth

const WEIGHTS = {            // Board evaluation weights
  empty: 15,
  smoothness: 1.5,
  monotonicity: 2.0,
  maxTile: 3.0,
  position: 4.0,
  levelDifference: 1.2,
  isolation: 2.5,
  adjDiff: -0.7
};

```

Technical Details
Algorithm
Expectimax search with alpha-beta pruning

Board state hashing for efficient memoization

Optimized move simulation with tile merging logic

Key Heuristics
Empty cell optimization

Tile position weighting matrix

Smoothness and monotonicity calculations

Adjacent tile difference penalties

Maximum tile value prioritization

Stress Testing Parameters
Generates transaction every 50ms (20 TPS per instance)

Maintains game state consistency through smart contract interactions

Tests blockchain throughput with continuous state updates

Disclaimer
This bot is intended for:

Educational purposes

Blockchain stress testing

Game strategy analysis

Use responsibly and in accordance with Monad testnet policies.

Donate: 0x78b1a5612044ec6e183a3e7f90cd891a0bedc160

