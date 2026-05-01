-- sql/002_seed_problems.sql
-- Run this after 001_algo_recommender_schema.sql

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Insert Skills (Hierarchical Dependencies)
-- -----------------------------------------------------------------------------
INSERT INTO skills (id, code, name, parent_skill_id) VALUES
    -- Foundation Level
    (1, 'fundamentals', 'Fundamentals', NULL),
    (2, 'arrays', 'Arrays', 1),
    (3, 'strings', 'Strings', 1),
    (4, 'logic', 'Algorithmic Logic', 1),

    -- Intermediate Level
    (5, 'intermediate', 'Intermediate Techniques', NULL),
    (6, 'hashing', 'Hash Maps / Hash Sets', 5),
    (7, 'two_pointers', 'Two Pointers', 5),
    (8, 'sliding_window', 'Sliding Window', 5),
    (9, 'prefix_sum', 'Prefix Sum', 5),

    -- Advanced Level
    (10, 'advanced', 'Advanced Data Structures', NULL),
    (11, 'trees', 'Tree Traversal', 10),
    (12, 'graphs', 'Graph Theory', 10),
    (13, 'bfs_dfs', 'BFS/DFS Search', 12),
    (14, 'dp', 'Dynamic Programming', 10),
    (15, 'backtracking', 'Backtracking', 10)
ON CONFLICT (id) DO NOTHING;

-- Reset sequence to avoid unique constraint errors later
SELECT setval('skills_id_seq', 15);

-- -----------------------------------------------------------------------------
-- 2. Insert Problems
-- Difficulty scale: -2.5 (Very Easy) to 2.5 (Very Hard)
-- -----------------------------------------------------------------------------
INSERT INTO problems (id, title, statement_difficulty, algorithmic_difficulty, difficulty_uncertainty) VALUES
    -- Easy Array / Math (Difficulty: -1.5)
    (1, 'Reverse an Array', -1.0, -1.5, 0.5),
    (2, 'Find Maximum Element', -1.2, -1.6, 0.5),
    (3, 'Count Even Numbers', -1.5, -1.8, 0.5),
    (4, 'Palindrome String', -0.5, -1.0, 0.5),
    (5, 'FizzBuzz', -1.5, -2.0, 0.5),

    -- Hash Maps & Arrays (Difficulty: -0.5)
    (6, 'Two Sum', 0.0, -0.5, 0.6),
    (7, 'Contains Duplicate', -0.5, -0.8, 0.6),
    (8, 'First Unique Character', -0.2, -0.5, 0.6),
    (9, 'Anagram Checker', -0.1, -0.4, 0.6),
    (10, 'Intersection of Arrays', 0.0, -0.5, 0.6),

    -- Two Pointers & Sliding Window (Difficulty: 0.2)
    (11, 'Move Zeroes to End', 0.2, 0.0, 0.7),
    (12, 'Remove Duplicates from Sorted', 0.1, 0.1, 0.7),
    (13, 'Max Sum Subarray of Size K', 0.5, 0.3, 0.7),
    (14, 'Longest Substring Without Repeats', 0.8, 0.5, 0.8),
    (15, 'Container With Most Water', 1.0, 0.4, 0.8),

    -- Prefix Sums (Difficulty: 0.5)
    (16, 'Range Sum Query', 0.0, 0.5, 0.7),
    (17, 'Subarray Sum Equals K', 0.8, 0.8, 0.8),
    (18, 'Product of Array Except Self', 1.2, 0.6, 0.8),

    -- Trees & Simple DFS (Difficulty: 1.0)
    (19, 'Maximum Depth of Binary Tree', 0.5, 0.8, 0.8),
    (20, 'Invert Binary Tree', 0.4, 0.9, 0.8),
    (21, 'Lowest Common Ancestor', 1.2, 1.2, 0.8),
    (22, 'Binary Tree Level Order Traversal', 0.8, 1.0, 0.8),
    
    -- Graphs & Advanced Searches (Difficulty: 1.5)
    (23, 'Number of Islands', 1.0, 1.4, 0.9),
    (24, 'Clone Graph', 1.2, 1.5, 0.9),
    (25, 'Course Schedule (Cycle Detect)', 1.5, 1.7, 0.9),
    (26, 'Word Ladder', 1.8, 1.8, 1.0),

    -- Dynamic Programming (Difficulty: 2.0)
    (27, 'Climbing Stairs', 0.5, 1.2, 0.8),
    (28, 'Coin Change', 1.0, 1.8, 0.9),
    (29, 'Longest Increasing Subsequence', 1.5, 2.1, 1.0),
    (30, 'Edit Distance', 1.8, 2.5, 1.0)
ON CONFLICT (id) DO NOTHING;

SELECT setval('problems_id_seq', 30);

-- -----------------------------------------------------------------------------
-- 3. Link Problems to Skills (Weights sum to 1.0)
-- -----------------------------------------------------------------------------
INSERT INTO problem_skills (problem_id, skill_id, weight) VALUES
    -- Arrays
    (1, 2, 1.0), 
    (2, 2, 1.0), 
    (3, 2, 0.8), (3, 4, 0.2), 
    (4, 3, 1.0), 
    (5, 4, 1.0),

    -- Hashing
    (6, 6, 0.8), (6, 2, 0.2),
    (7, 6, 1.0),
    (8, 6, 0.6), (8, 3, 0.4),
    (9, 6, 0.7), (9, 3, 0.3),
    (10, 6, 0.5), (10, 2, 0.5),

    -- Pointers / Sliding Window
    (11, 7, 1.0),
    (12, 7, 1.0),
    (13, 8, 1.0),
    (14, 8, 0.6), (14, 6, 0.4), -- Window + Hash
    (15, 7, 0.9), (15, 4, 0.1),

    -- Prefix Sums
    (16, 9, 1.0),
    (17, 9, 0.6), (17, 6, 0.4), -- Prefix Sum + Hash
    (18, 9, 1.0),

    -- Trees 
    (19, 11, 0.6), (19, 13, 0.4), -- Tree + DFS
    (20, 11, 0.6), (20, 13, 0.4),
    (21, 11, 0.5), (21, 13, 0.5),
    (22, 11, 0.5), (22, 13, 0.5), -- Specifically BFS

    -- Graphs
    (23, 12, 0.3), (23, 13, 0.7), -- Graph Search (DFS/BFS)
    (24, 12, 0.5), (24, 13, 0.3), (24, 6, 0.2), -- Graph + DFS + HashMap
    (25, 12, 0.6), (25, 13, 0.4),
    (26, 12, 0.5), (26, 13, 0.5), -- BFS shortest path

    -- Dynamic Programming
    (27, 14, 1.0),
    (28, 14, 1.0),
    (29, 14, 1.0),
    (30, 14, 0.8), (30, 3, 0.2) -- DP on Strings
ON CONFLICT (problem_id, skill_id) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 4. Initialize Problem Rating States
-- The algorithm uses these baseline difficulties to predict win probability 
-- -----------------------------------------------------------------------------
INSERT INTO problem_rating_state (problem_id, difficulty, uncertainty, attempts, solves, first_try_solves)
SELECT 
    id, 
    algorithmic_difficulty + (statement_difficulty * 0.2) AS base_difficulty, 
    difficulty_uncertainty, 
    0, 0, 0
FROM problems
ON CONFLICT (problem_id) DO NOTHING;

COMMIT;
