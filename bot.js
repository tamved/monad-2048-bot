(function() {
    console.log('[BOT] Initializing...');
    
    const MOVE_INTERVAL = 50;
    const TILE_SELECTOR = '[class*="absolute"][style*="top: calc"]';
    let isRunning = true;
    let moveCount = 0;
    const SEARCH_DEPTH = 5;
    const TRANSPOSITION_TABLE = new Map();
    const LOG2 = new Map();

    for (let i = 1; i <= 17; i++) {
        LOG2.set(1 << i, i);
    }

    const WEIGHTS = {
        empty: 15,
        smoothness: 1.5,
        monotonicity: 2.0,
        maxTile: 3.0,
        position: 4.0,
        levelDifference: 1.2,
        isolation: 2.5,
        adjDiff: -0.7
    };

    const POSITION_WEIGHTS = [
        65536, 32768, 16384,  8192,
        512,   1024,  2048,   4096,
        256,    128,    64,    32,
        16,      8,     4,     2
    ];

    const intervalId = setInterval(() => {
        if (!isRunning) return;
        try {
            TRANSPOSITION_TABLE.clear();
            const grid = parseGrid();
            const move = calculateBestMove(grid);
            sendMove(move);
            console.log(`[BOT] Move #${++moveCount}: ${move}`);
        } catch (error) {
            console.error('[BOT] Error:', error);
        }
    }, MOVE_INTERVAL);

    function parseGrid() {
        const grid = new Array(16).fill(0);
        document.querySelectorAll(TILE_SELECTOR).forEach(tile => {
            try {
                const value = parseInt(tile.textContent) || 0;
                if (!value) return;

                const style = tile.getAttribute('style');
                if (!style) return;

                const getPosition = (prop) => {
                    const match = style.match(new RegExp(`${prop}:\\s*calc\\((\\d+)%`));
                    return match ? parseInt(match[1]) : 0;
                };

                const top = getPosition('top');
                const left = getPosition('left');
                const row = Math.floor(top / 25);
                const col = Math.floor(left / 25);
                const index = row * 4 + col;

                if (index >= 0 && index < 16) {
                    grid[index] = value;
                }
            } catch(e) {
                console.warn('Tile parsing error:', e);
            }
        });
        return grid;
    }

    function sendMove(key) {
        const event = new KeyboardEvent('keydown', {
            key: key,
            keyCode: { 
                ArrowUp: 38, 
                ArrowDown: 40, 
                ArrowLeft: 37, 
                ArrowRight: 39 
            }[key],
            bubbles: true,
            composed: true
        });
        document.dispatchEvent(event);
    }

    function calculateBestMove(grid) {
        const moves = ['ArrowRight', 'ArrowDown', 'ArrowLeft', 'ArrowUp'];
        let bestScore = -Infinity;
        let bestMove = 'ArrowRight';
        
        for (const move of moves) {
            const newGrid = simulateMove(grid, move);
            if (!newGrid) continue;
            
            const score = expectimax(newGrid, SEARCH_DEPTH - 1, false);
            if (score > bestScore) {
                bestScore = score;
                bestMove = move;
            }
        }
        
        return bestMove;
    }

    function expectimax(grid, depth, isPlayer, alpha = -Infinity, beta = Infinity) {
        const key = getGridKey(grid, depth, isPlayer);
        if (TRANSPOSITION_TABLE.has(key)) {
            return TRANSPOSITION_TABLE.get(key);
        }
        
        if (depth === 0) return evaluateGrid(grid);
        
        let result;
        if (isPlayer) {
            let maxScore = -Infinity;
            for (const move of ['ArrowRight', 'ArrowDown', 'ArrowLeft', 'ArrowUp']) {
                const newGrid = simulateMove(grid, move);
                if (!newGrid) continue;
                
                const score = expectimax(newGrid, depth - 1, false, alpha, beta);
                if (score > maxScore) {
                    maxScore = score;
                    if (maxScore >= beta) break;
                    alpha = Math.max(alpha, maxScore);
                }
            }
            result = maxScore === -Infinity ? 0 : maxScore;
        } else {
            let emptyCells = [];
            for (let i = 0; i < 16; i++) {
                if (grid[i] === 0) emptyCells.push(i);
            }
            
            if (emptyCells.length === 0) {
                result = evaluateGrid(grid);
            } else {
                let totalScore = 0;
                const probability4 = 0.1;
                
                for (const index of emptyCells) {
                    const grid2 = [...grid];
                    grid2[index] = 2;
                    totalScore += (1 - probability4) * expectimax(grid2, depth - 1, true, alpha, beta);
                    
                    const grid4 = [...grid];
                    grid4[index] = 4;
                    totalScore += probability4 * expectimax(grid4, depth - 1, true, alpha, beta);
                }
                result = totalScore / emptyCells.length;
            }
        }
        
        TRANSPOSITION_TABLE.set(key, result);
        return result;
    }

    function simulateMove(originalGrid, direction) {
        const grid = [...originalGrid];
        let moved = false;
        
        const processLine = (line) => {
            let merged = [];
            let prev = null;
            for (const tile of line.filter(c => c !== 0)) {
                if (prev === tile) {
                    merged.push(tile * 2);
                    prev = null;
                    moved = true;
                } else {
                    if (prev !== null) merged.push(prev);
                    prev = tile;
                }
            }
            if (prev !== null) merged.push(prev);
            return merged.concat(Array(4 - merged.length).fill(0));
        };

        for (let i = 0; i < 4; i++) {
            let line = [];
            for (let j = 0; j < 4; j++) {
                line.push(
                    direction === 'ArrowLeft' ? grid[i * 4 + j] :
                    direction === 'ArrowRight' ? grid[i * 4 + (3 - j)] :
                    direction === 'ArrowUp' ? grid[j * 4 + i] :
                    grid[(3 - j) * 4 + i]
                );
            }
            
            const processed = processLine(line);
            
            for (let j = 0; j < 4; j++) {
                const index = 
                    direction === 'ArrowLeft' ? i * 4 + j :
                    direction === 'ArrowRight' ? i * 4 + (3 - j) :
                    direction === 'ArrowUp' ? j * 4 + i :
                    (3 - j) * 4 + i;
                
                if (grid[index] !== processed[j]) moved = true;
                grid[index] = processed[j];
            }
        }
        
        return moved ? grid : null;
    }

    function evaluateGrid(grid) {
        let empty = 0;
        let smoothness = 0;
        let monotonicity = 0;
        let maxTile = 0;
        let positionScore = 0;
        let levelDifference = 0;
        let isolation = 0;
        let adjDiff = 0;
        
        for (let i = 0; i < 16; i++) {
            const val = grid[i];
            if (val === 0) {
                empty++;
                continue;
            }
            
            maxTile = Math.max(maxTile, val);
            positionScore += val * POSITION_WEIGHTS[i];
        }
        
        for (let i = 0; i < 16; i++) {
            const val = grid[i];
            if (val === 0) continue;
            
            const logVal = LOG2.get(val);
            const row = Math.floor(i / 4);
            const col = i % 4;
            
            const checkNeighbor = (r, c) => {
                if (r >= 0 && r < 4 && c >= 0 && c < 4) {
                    const neighbor = grid[r * 4 + c];
                    if (neighbor !== 0) {
                        const logNeighbor = LOG2.get(neighbor);
                        levelDifference += Math.abs(logVal - logNeighbor);
                        smoothness -= Math.abs(val - neighbor);
                        adjDiff += Math.abs(logVal - logNeighbor) * Math.log2(val + neighbor);
                    }
                }
            };
            
            checkNeighbor(row - 1, col);
            checkNeighbor(row + 1, col);
            checkNeighbor(row, col - 1);
            checkNeighbor(row, col + 1);
            
            if (col < 3) {
                const right1 = grid[i + 1];
                if (col < 2) {
                    const right2 = grid[i + 2];
                    if (right1 && right2 && Math.abs(logVal - LOG2.get(right2)) <= 1) {
                        isolation += Math.abs(logVal - LOG2.get(right1)) * val;
                    }
                }
            }
        }
        
        for (let row = 0; row < 4; row++) {
            for (let col = 0; col < 3; col++) {
                const current = grid[row * 4 + col];
                const next = grid[row * 4 + col + 1];
                if (current && next) {
                    monotonicity += Math.abs(LOG2.get(current) - LOG2.get(next));
                }
            }
        }
        for (let col = 0; col < 4; col++) {
            for (let row = 0; row < 3; row++) {
                const current = grid[row * 4 + col];
                const next = grid[(row + 1) * 4 + col];
                if (current && next) {
                    monotonicity += Math.abs(LOG2.get(current) - LOG2.get(next));
                }
            }
        }
        
        return (
            empty * empty * WEIGHTS.empty +
            smoothness * WEIGHTS.smoothness +
            positionScore * WEIGHTS.position +
            maxTile * WEIGHTS.maxTile -
            monotonicity * WEIGHTS.monotonicity -
            levelDifference * WEIGHTS.levelDifference -
            isolation * WEIGHTS.isolation +
            adjDiff * WEIGHTS.adjDiff
        );
    }

    function getGridKey(grid, depth, isPlayer) {
        let hash1 = 0, hash2 = 0;
        for (let i = 0; i < grid.length; i++) {
            const val = grid[i];
            if (val) {
                const key = (LOG2.get(val) || 0) * 16 + i;
                hash1 ^= (key * 2654435761) & 0xFFFFFFFF;
                hash2 ^= (key * 2246822519) & 0xFFFFFFFF;
            }
        }
        return `${hash1}|${hash2}|${depth}|${isPlayer}`;
    }
})();
