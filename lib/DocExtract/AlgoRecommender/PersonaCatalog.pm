package DocExtract::AlgoRecommender::PersonaCatalog;

use strict;
use warnings;

sub all_personas {
    return [
        {
            user_id => 9001,
            slug => 'beginner-fundamentals',
            name => 'Beginner Fundamentals',
            description => 'New learner with weak fundamentals who improves on very easy logic and array work.',
            initial_global_ability => -0.85,
            initial_skills => [
                { skill_code => 'arrays', ability => -0.45, uncertainty => 0.95, attempts => 3, solves => 1 },
                { skill_code => 'strings', ability => -0.35, uncertainty => 0.95, attempts => 2, solves => 1 },
                { skill_code => 'logic', ability => -0.55, uncertainty => 0.98, attempts => 4, solves => 1 },
            ],
            pre_solved_problem_ids => [],
            submissions => [
                { problem_id => 5, verdict => 'wrong_answer', tests_passed => 6, tests_total => 10, created_at => '2026-05-01T09:00:00Z' },
                { problem_id => 5, verdict => 'accepted', created_at => '2026-05-01T09:12:00Z' },
                { problem_id => 1, verdict => 'accepted', created_at => '2026-05-01T09:25:00Z' },
            ],
        },
        {
            user_id => 9002,
            slug => 'beginner-arrays-strings',
            name => 'Beginner Arrays and Strings',
            description => 'Comfortable with simple strings and arrays, but not yet ready for compound patterns.',
            initial_global_ability => -0.45,
            initial_skills => [
                { skill_code => 'arrays', ability => 0.05, uncertainty => 0.90, attempts => 6, solves => 4 },
                { skill_code => 'strings', ability => 0.10, uncertainty => 0.88, attempts => 5, solves => 4 },
                { skill_code => 'hashing', ability => -0.25, uncertainty => 0.95, attempts => 2, solves => 0 },
            ],
            pre_solved_problem_ids => [1, 4],
            submissions => [
                { problem_id => 9, verdict => 'wrong_answer', tests_passed => 4, tests_total => 10, created_at => '2026-05-01T09:05:00Z' },
                { problem_id => 9, verdict => 'accepted', created_at => '2026-05-01T09:18:00Z' },
                { problem_id => 10, verdict => 'accepted', created_at => '2026-05-01T09:34:00Z' },
            ],
        },
        {
            user_id => 9003,
            slug => 'intermediate-window-hash',
            name => 'Intermediate Window and Hashing',
            description => 'Good with medium array patterns and improving toward richer sliding-window problems.',
            initial_global_ability => 0.15,
            initial_skills => [
                { skill_code => 'hashing', ability => 0.35, uncertainty => 0.60, attempts => 12, solves => 8 },
                { skill_code => 'two_pointers', ability => 0.25, uncertainty => 0.62, attempts => 10, solves => 7 },
                { skill_code => 'sliding_window', ability => 0.15, uncertainty => 0.68, attempts => 8, solves => 5 },
            ],
            pre_solved_problem_ids => [6, 7, 11, 12],
            submissions => [
                { problem_id => 14, verdict => 'wrong_answer', tests_passed => 7, tests_total => 10, created_at => '2026-05-01T09:10:00Z' },
                { problem_id => 14, verdict => 'accepted', created_at => '2026-05-01T09:24:00Z' },
                { problem_id => 17, verdict => 'accepted', created_at => '2026-05-01T09:40:00Z' },
            ],
        },
        {
            user_id => 9004,
            slug => 'graph-specialist',
            name => 'Graph Specialist',
            description => 'Strong on graph traversal and cycle detection, weak when a problem shifts to DP.',
            initial_global_ability => 0.40,
            initial_skills => [
                { skill_code => 'graphs', ability => 0.95, uncertainty => 0.35, attempts => 20, solves => 16 },
                { skill_code => 'bfs_dfs', ability => 0.85, uncertainty => 0.30, attempts => 22, solves => 18 },
                { skill_code => 'dp', ability => -0.55, uncertainty => 0.85, attempts => 5, solves => 1 },
            ],
            pre_solved_problem_ids => [19, 20, 23],
            submissions => [
                { problem_id => 25, verdict => 'accepted', created_at => '2026-05-01T09:00:00Z' },
                { problem_id => 28, verdict => 'wrong_answer', tests_passed => 2, tests_total => 10, created_at => '2026-05-01T09:20:00Z' },
            ],
        },
        {
            user_id => 9005,
            slug => 'dp-specialist',
            name => 'DP Specialist',
            description => 'Comfortable with dynamic programming but shaky on graph search and traversal.',
            initial_global_ability => 0.42,
            initial_skills => [
                { skill_code => 'dp', ability => 0.95, uncertainty => 0.35, attempts => 18, solves => 14 },
                { skill_code => 'strings', ability => 0.25, uncertainty => 0.55, attempts => 8, solves => 6 },
                { skill_code => 'graphs', ability => -0.40, uncertainty => 0.88, attempts => 4, solves => 1 },
                { skill_code => 'bfs_dfs', ability => -0.35, uncertainty => 0.88, attempts => 4, solves => 1 },
            ],
            pre_solved_problem_ids => [27],
            submissions => [
                { problem_id => 28, verdict => 'accepted', created_at => '2026-05-01T09:08:00Z' },
                { problem_id => 23, verdict => 'wrong_answer', tests_passed => 3, tests_total => 10, created_at => '2026-05-01T09:28:00Z' },
            ],
        },
        {
            user_id => 9006,
            slug => 'tree-dfs-learner',
            name => 'Tree and DFS Learner',
            description => 'Developing recursion and traversal skills, with most confidence on trees.',
            initial_global_ability => 0.05,
            initial_skills => [
                { skill_code => 'trees', ability => 0.30, uncertainty => 0.70, attempts => 9, solves => 6 },
                { skill_code => 'bfs_dfs', ability => 0.22, uncertainty => 0.75, attempts => 8, solves => 5 },
                { skill_code => 'graphs', ability => 0.00, uncertainty => 0.85, attempts => 4, solves => 2 },
            ],
            pre_solved_problem_ids => [19],
            submissions => [
                { problem_id => 22, verdict => 'accepted', created_at => '2026-05-01T09:05:00Z' },
                { problem_id => 24, verdict => 'wrong_answer', tests_passed => 5, tests_total => 10, created_at => '2026-05-01T09:27:00Z' },
            ],
        },
        {
            user_id => 9007,
            slug => 'well-rounded-intermediate',
            name => 'Well Rounded Intermediate',
            description => 'Balanced intermediate learner with mild weakness in harder graph and DP tasks.',
            initial_global_ability => 0.28,
            initial_skills => [
                { skill_code => 'arrays', ability => 0.35, uncertainty => 0.55, attempts => 10, solves => 8 },
                { skill_code => 'strings', ability => 0.28, uncertainty => 0.60, attempts => 9, solves => 7 },
                { skill_code => 'hashing', ability => 0.30, uncertainty => 0.58, attempts => 11, solves => 8 },
                { skill_code => 'two_pointers', ability => 0.18, uncertainty => 0.65, attempts => 8, solves => 5 },
                { skill_code => 'prefix_sum', ability => 0.10, uncertainty => 0.70, attempts => 7, solves => 4 },
                { skill_code => 'graphs', ability => -0.05, uncertainty => 0.80, attempts => 5, solves => 2 },
                { skill_code => 'dp', ability => -0.10, uncertainty => 0.82, attempts => 5, solves => 2 },
            ],
            pre_solved_problem_ids => [2, 6, 11],
            submissions => [
                { problem_id => 17, verdict => 'accepted', created_at => '2026-05-01T09:03:00Z' },
                { problem_id => 23, verdict => 'wrong_answer', tests_passed => 7, tests_total => 10, created_at => '2026-05-01T09:21:00Z' },
                { problem_id => 23, verdict => 'accepted', created_at => '2026-05-01T09:42:00Z' },
            ],
        },
        {
            user_id => 9008,
            slug => 'inconsistent-learner',
            name => 'Inconsistent Learner',
            description => 'Can solve some medium problems but frequently misfires and accumulates failed attempts.',
            initial_global_ability => -0.08,
            initial_skills => [
                { skill_code => 'arrays', ability => 0.12, uncertainty => 0.75, attempts => 9, solves => 5 },
                { skill_code => 'hashing', ability => 0.05, uncertainty => 0.80, attempts => 7, solves => 4 },
                { skill_code => 'graphs', ability => -0.22, uncertainty => 0.88, attempts => 5, solves => 1 },
                { skill_code => 'sliding_window', ability => -0.12, uncertainty => 0.84, attempts => 5, solves => 2 },
            ],
            pre_solved_problem_ids => [3, 7],
            submissions => [
                { problem_id => 14, verdict => 'wrong_answer', tests_passed => 4, tests_total => 10, created_at => '2026-05-01T09:06:00Z' },
                { problem_id => 14, verdict => 'wrong_answer', tests_passed => 6, tests_total => 10, created_at => '2026-05-01T09:18:00Z' },
                { problem_id => 23, verdict => 'wrong_answer', tests_passed => 3, tests_total => 10, created_at => '2026-05-01T09:37:00Z' },
            ],
        },
        {
            user_id => 9009,
            slug => 'fast-improver',
            name => 'Fast Improver',
            description => 'Starts near beginner level but adapts quickly after a few successful runs.',
            initial_global_ability => -0.35,
            initial_skills => [
                { skill_code => 'arrays', ability => 0.00, uncertainty => 0.90, attempts => 4, solves => 2 },
                { skill_code => 'hashing', ability => -0.10, uncertainty => 0.92, attempts => 3, solves => 1 },
                { skill_code => 'two_pointers', ability => -0.18, uncertainty => 0.94, attempts => 2, solves => 0 },
            ],
            pre_solved_problem_ids => [],
            submissions => [
                { problem_id => 6, verdict => 'wrong_answer', tests_passed => 5, tests_total => 10, created_at => '2026-05-01T09:00:00Z' },
                { problem_id => 6, verdict => 'accepted', created_at => '2026-05-01T09:13:00Z' },
                { problem_id => 13, verdict => 'accepted', created_at => '2026-05-01T09:29:00Z' },
                { problem_id => 14, verdict => 'accepted', created_at => '2026-05-01T09:46:00Z' },
            ],
        },
        {
            user_id => 9010,
            slug => 'advanced-all-rounder',
            name => 'Advanced All Rounder',
            description => 'Strong across the board and mostly benefits from hard graph and DP challenges.',
            initial_global_ability => 1.05,
            initial_skills => [
                { skill_code => 'arrays', ability => 0.65, uncertainty => 0.25, attempts => 18, solves => 16 },
                { skill_code => 'strings', ability => 0.60, uncertainty => 0.25, attempts => 16, solves => 14 },
                { skill_code => 'hashing', ability => 0.72, uncertainty => 0.24, attempts => 18, solves => 15 },
                { skill_code => 'two_pointers', ability => 0.58, uncertainty => 0.26, attempts => 15, solves => 13 },
                { skill_code => 'prefix_sum', ability => 0.55, uncertainty => 0.28, attempts => 14, solves => 12 },
                { skill_code => 'trees', ability => 0.78, uncertainty => 0.22, attempts => 20, solves => 17 },
                { skill_code => 'graphs', ability => 0.90, uncertainty => 0.20, attempts => 24, solves => 20 },
                { skill_code => 'bfs_dfs', ability => 0.88, uncertainty => 0.20, attempts => 24, solves => 20 },
                { skill_code => 'dp', ability => 0.85, uncertainty => 0.22, attempts => 21, solves => 17 },
            ],
            pre_solved_problem_ids => [1, 6, 11, 16, 19, 23, 27],
            submissions => [
                { problem_id => 26, verdict => 'accepted', created_at => '2026-05-01T09:04:00Z' },
                { problem_id => 29, verdict => 'accepted', created_at => '2026-05-01T09:26:00Z' },
                { problem_id => 30, verdict => 'accepted', created_at => '2026-05-01T09:51:00Z' },
            ],
        },
    ];
}

1;
