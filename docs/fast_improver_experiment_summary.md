# Fast Improver Experiment Summary

Source report: `docs/algo_recommender_experiment_report.json`

This summary extracts one learner from the experiment report: `Fast Improver`, user `9009`.

## User Overview

`Fast Improver` starts near beginner level, then improves quickly after solving hashing and
sliding-window style problems. Their global ability moved from `-0.3500` to `-0.3041`, so the
system learned that they are stronger than their initial profile suggested.

## Submission Replay

| Problem | Result | Predicted | Observed | Effect |
|---|---:|---:|---:|---|
| `Two Sum` | wrong answer | `0.517` | `0.300` | user underperformed, problem got slightly harder |
| `Two Sum` | accepted | `0.510` | `0.850` | user improved, problem got easier |
| `Max Sum Subarray of Size K` | accepted | `0.322` | `1.000` | strong overperformance |
| `Longest Substring Without Repeats` | accepted | `0.275` | `1.000` | very strong overperformance |

## Skill Progress

| Skill | Before | After |
|---|---:|---:|
| `arrays` | `0.0000` | `0.0019` |
| `hashing` | `-0.1000` | `-0.0690` |
| `two_pointers` | `-0.1800` | `-0.1800` |
| `sliding_window` | not present | `0.0891` |

## Problem Progress

| Problem | Seed Difficulty | Current Difficulty | Meaning |
|---|---:|---:|---|
| `Two Sum` | `-0.5000` | `-0.5061` | slightly easier after the final accepted solve |
| `Max Sum Subarray of Size K` | `0.4000` | `0.3661` | easier because the user solved it despite low predicted probability |
| `Longest Substring Without Repeats` | `0.6600` | `0.6047` | easier overall after experiment users performed well on it |

Important nuance: `current_difficulty` is the result after the whole experiment run, so for
`Longest Substring Without Repeats` it includes other synthetic users too, not only user `9009`.

## Final Recommendations

| Rank | Problem | Solve Probability | Score |
|---:|---|---:|---:|
| 1 | `Palindrome String` | `0.689` | `0.856` |
| 2 | `Contains Duplicate` | `0.629` | `0.790` |
| 3 | `Reverse an Array` | `0.805` | `0.789` |
| 4 | `Find Maximum Element` | `0.823` | `0.780` |
| 5 | `FizzBuzz` | `0.879` | `0.771` |

## Interpretation

For this user, the next best recommendation is `Palindrome String`: it is still approachable, but
not too trivial, and it keeps them practicing foundational pattern recognition before moving deeper
into harder sliding-window and hash-map problems.
