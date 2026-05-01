# Mathematical Model of the Algorithm-Practice Recommendation System

## Abstract

This document describes the mathematical model implemented by the
algorithm-practice recommendation system. The system is an online, multi-skill
rating model for programming exercises. It estimates a user's probability of
solving a problem from skill-specific abilities, global ability, problem skill
weights, and problem difficulty. After each submission, it converts the
submission outcome into an observed credit value, compares that observation with
the predicted probability, and uses the prediction error to update user skill
abilities, user global ability, and problem difficulty.

The model is similar in spirit to a Rasch or item-response model, extended with
multiple skills per problem and simple stochastic-gradient-style updates. It is
not a fully Bayesian model: the stored uncertainty values are deterministic
confidence indicators that decay with practice rather than posterior
distributions.

## Scope

The system has two connected parts:

1. The rating system, which updates user and problem state after submissions.
2. The recommendation system, which ranks unsolved candidate problems using the
   current rating state.

The rating system is the source of the latent variables used by recommendation:
user skill ability, user global ability, and problem difficulty. The
recommendation system then turns these variables into a ranked list of problems
that should be challenging, useful, and not excessively frustrating.

## Notation

Let:

- `u` denote a user.
- `p` denote a problem.
- `s` denote a skill.
- `S_p` denote the set of skills attached to problem `p`.
- `w_{p,s}` denote the weight of skill `s` in problem `p`.
- `a_{u,s}` denote user `u`'s ability for skill `s`.
- `g_u` denote user `u`'s global ability bias.
- `d_p` denote problem `p`'s difficulty.
- `q_{u,s}` denote the uncertainty stored for user `u` and skill `s`.
- `q_p` denote the uncertainty stored for problem `p`.
- `c` denote observed submission credit.
- `e` denote prediction error.
- `eta_u` denote the user skill learning rate, implemented as `user_k`.
- `eta_p` denote the problem difficulty learning rate, implemented as
  `problem_k`.
- `rho` denote the uncertainty decay factor, implemented as
  `uncertainty_decay`.
- `q_min` denote the minimum allowed uncertainty, implemented as
  `min_uncertainty`.

The default implementation values are:

```text
eta_u = 0.08
eta_p = 0.05
rho   = 0.97
q_min = 0.15
```

The logistic sigmoid is:

```text
sigma(x) = 1 / (1 + exp(-x))
```

The implementation clamps extreme sigmoid inputs to avoid numerical overflow:
values greater than or equal to `35` return `1`, and values less than or equal
to `-35` return `0`.

## Conceptual Overview

Each problem is represented as a weighted mixture of skills. For example, a
graph traversal problem might be represented as:

```text
graphs: 0.70
bfs_dfs: 0.30
```

The user's effective ability for a problem is the weighted sum of the user's
abilities in those skills, plus a global ability term:

```text
theta_{u,p} = g_u + sum_{s in S_p}(w_{p,s} * a_{u,s})
```

The system compares this effective ability with the problem difficulty. If the
user's effective ability is much greater than the problem difficulty, the
predicted probability of solving the problem is high. If it is much smaller,
the predicted probability is low.

After a submission, the system computes an observed credit value between `0`
and `1`. A first-try accepted solution receives full credit. Later accepted
solutions, hints, editorials, and partial test progress modify this credit.
The update signal is the difference between observed credit and predicted
probability:

```text
e = c - P_hat(u solves p)
```

This error drives all rating updates:

- If `e > 0`, the user performed better than expected.
- If `e < 0`, the user performed worse than expected.
- If `e = 0`, the result matched the model's expectation.

The user skill update and problem difficulty update move in opposite
directions:

- Better-than-expected performance increases the relevant user skills.
- Better-than-expected performance decreases the problem difficulty.
- Worse-than-expected performance decreases the relevant user skills.
- Worse-than-expected performance increases the problem difficulty.

## Prediction Model

For a problem `p`, the model first computes the user's weighted skill ability:

```text
A_{u,p} = sum_{s in S_p}(w_{p,s} * a_{u,s})
```

The global ability bias is then added:

```text
theta_{u,p} = A_{u,p} + g_u
```

The predicted probability of solving the problem is:

```text
P_hat(u solves p) = sigma(theta_{u,p} - d_p)
```

Equivalently:

```text
P_hat(u solves p) = 1 / (1 + exp(-(theta_{u,p} - d_p)))
```

This means the model is centered around the condition:

```text
theta_{u,p} = d_p
```

When effective user ability equals problem difficulty, the predicted solve
probability is:

```text
sigma(0) = 0.5
```

If `theta_{u,p}` is greater than `d_p`, the solve probability rises above
`0.5`. If `theta_{u,p}` is lower than `d_p`, the solve probability falls below
`0.5`.

## Observed Credit Model

The raw submission outcome is converted into a continuous credit value `c`.
This lets the model learn from more than a binary pass/fail event.

### Accepted submissions

For verdicts `accepted` or `ac`, the base credit depends on the number of
previous attempts by this user on the same problem:

```text
base_credit = 1.00  if prior_attempts = 0
base_credit = 0.85  if prior_attempts >= 1
base_credit = 0.70  if prior_attempts >= 3
```

The implementation applies these thresholds in order, so `prior_attempts >= 3`
receives base credit `0.70`.

Help usage then reduces the credit:

```text
c_raw = base_credit - 0.10 * hint_used - 0.15 * editorial_used
```

The accepted credit is clamped:

```text
c = clamp(c_raw, 0.25, 1.00)
```

This means an accepted submission always receives at least `0.25` credit, but
it may still fall below the system's solve threshold if it required many
attempts and help.

### Non-accepted submissions with test progress

If the submission is not accepted but has `tests_passed` and `tests_total`, the
system gives partial credit:

```text
c_raw = 0.60 * (tests_passed / tests_total)
        - 0.05 * hint_used
        - 0.10 * editorial_used
```

The partial credit is clamped:

```text
c = clamp(c_raw, 0.00, 0.60)
```

Partial progress can therefore teach the model that the user is closer to
mastering a problem than a pure failure would indicate, but it cannot count as
a strong solve signal.

### Other failed submissions

If the submission is not accepted and has no usable test-progress information,
the observed credit is:

```text
c = 0
```

### Solve indicator

The system marks a submission as solved when:

```text
solved = 1 if c >= 0.70
solved = 0 otherwise
```

This threshold is important. A heavily discounted accepted solution may update
the ratings positively while still not being counted as solved by the state
update.

## Prediction Error

Given observed credit `c` and predicted probability `P_hat`, the model computes:

```text
e = c - P_hat
```

The error is the core learning signal.

Interpretation:

- `e > 0`: the user exceeded expectations.
- `e < 0`: the user underperformed expectations.
- `|e|` large: the result was surprising.
- `|e|` small: the model prediction was close to the observed outcome.

Because both `c` and `P_hat` are in `[0, 1]`, the error is bounded:

```text
-1 <= e <= 1
```

## Skill Ability Update

For every skill `s` attached to problem `p`, the model updates the user's
skill ability using the skill weight and the prediction error:

```text
Delta a_{u,s} = eta_u * w_{p,s} * e
```

The new skill ability is:

```text
a'_{u,s} = a_{u,s} + Delta a_{u,s}
```

Substituting the delta:

```text
a'_{u,s} = a_{u,s} + eta_u * w_{p,s} * (c - P_hat)
```

This is a local online update. Only the skills attached to the attempted
problem are updated. Skills with larger weights receive larger updates.

### Skill update behavior

If a problem is 70 percent graphs and 30 percent BFS/DFS, then the graph skill
receives a larger share of the update:

```text
Delta a_{u,graphs} = eta_u * 0.70 * e
Delta a_{u,bfsdfs} = eta_u * 0.30 * e
```

If the user does better than expected, both deltas are positive. If the user
does worse than expected, both deltas are negative.

### Skill uncertainty update

The skill uncertainty decays after practice:

```text
q'_{u,s} = clamp(q_{u,s} * rho, q_min, 1)
```

With the default `rho = 0.97`, each practiced skill becomes slightly less
uncertain after each attempt, but uncertainty cannot fall below `q_min`.

This is not a Bayesian posterior update. It is a deterministic confidence
decay: more observations make the system less uncertain about the user's
ability in that skill.

### Skill counters

For each practiced skill, the system also updates counters:

```text
skill_attempts' = skill_attempts + 1
skill_solves'   = skill_solves + solved
```

The last practice timestamp is set to the submission timestamp.

### Mastery probability

The implementation can project a skill ability into a mastery-like probability:

```text
mastery_{u,s} = sigma(a_{u,s})
```

This transformation is used by the recommendation scorer when measuring weak
skill coverage. A skill ability near zero maps to mastery near `0.5`; positive
ability maps above `0.5`; negative ability maps below `0.5`.

## Global Ability Update

In addition to per-skill abilities, the system stores a global ability bias
`g_u`. This captures broad user strength that is not specific to a single
skill.

The global update is:

```text
g'_u = g_u + 0.03 * e
```

This is smaller than the default skill learning rate. It lets repeated
overperformance or underperformance gradually move the user's general baseline
without overwhelming skill-specific evidence.

## Problem Difficulty Update

The problem difficulty update uses the same prediction error but with the
opposite sign:

```text
Delta d_p = -eta_p * e
```

The new problem difficulty is:

```text
d'_p = d_p + Delta d_p
```

Equivalently:

```text
d'_p = d_p - eta_p * (c - P_hat)
```

### Interpretation

If the user performs better than expected:

```text
e > 0
Delta d_p < 0
d'_p < d_p
```

The problem is adjusted downward because it appeared easier than the model
expected for this user state.

If the user performs worse than expected:

```text
e < 0
Delta d_p > 0
d'_p > d_p
```

The problem is adjusted upward because it appeared harder than the model
expected.

The problem update is intentionally smaller than the user skill update by
default:

```text
eta_p = 0.05
eta_u = 0.08
```

This causes problem difficulty to move more conservatively than user skill
ability.

### Problem uncertainty update

The problem uncertainty decays similarly to skill uncertainty:

```text
q'_p = clamp(q_p * rho, q_min, 1)
```

Every attempt gives the model more evidence about the problem, so uncertainty
declines until it reaches the configured floor.

### Problem counters

The problem rating state also tracks aggregate counters:

```text
problem_attempts'        = problem_attempts + 1
problem_solves'          = problem_solves + solved
problem_first_try_solves'= problem_first_try_solves + first_try_solve
```

Where:

```text
first_try_solve = solved AND prior_user_problem_attempts = 0
```

## User-Problem State Update

The model also maintains state for each `(user, problem)` pair:

```text
user_problem_attempts' = user_problem_attempts + 1
```

The solved flag is persistent:

```text
user_problem_solved' = user_problem_solved OR solved
```

If this is the first time the user solved the problem, the system records
`first_solved_at`. It also records `last_attempt_at` for cooldown filtering in
the recommendation system.

## Full Rating Update Algorithm

For a submission by user `u` on problem `p`, the model performs the following
steps:

1. Load and lock the problem rating state.
2. Load the skills and weights attached to the problem.
3. Load and lock the user's state for this problem.
4. Load and lock the user's skill states for the problem's skills.
5. Load and lock the user's global ability state.
6. Compute observed credit `c`.
7. Predict solve probability `P_hat`.
8. Compute error `e = c - P_hat`.
9. Update each relevant skill ability:

   ```text
   a'_{u,s} = a_{u,s} + eta_u * w_{p,s} * e
   ```

10. Update user global ability:

    ```text
    g'_u = g_u + 0.03 * e
    ```

11. Update problem difficulty:

    ```text
    d'_p = d_p - eta_p * e
    ```

12. Decay skill and problem uncertainty.
13. Update attempts, solves, first-solve, and last-attempt timestamps.
14. Commit the transaction.

The transaction ensures that related user and problem states are updated
together.

## Recommendation Scoring Model

The recommendation system ranks candidate problems using the rating state. It
first excludes problems that the user has already solved. By default, it also
excludes problems attempted recently, using a cooldown period of three days.

For each remaining candidate problem, it computes a recommendation score from
five components:

1. Challenge fit.
2. Weak skill coverage.
3. Uncertainty reduction.
4. Novelty.
5. Frustration risk.

### Challenge fit

The recommender has a target solve probability:

```text
tau = 0.72
```

Challenge fit rewards problems whose predicted solve probability is close to
this target:

```text
challenge_fit = 1 - clamp(abs(P_hat - tau) / tau, 0, 1)
```

This favors problems that are neither too easy nor too hard.

### Weak skill coverage

For each skill in the problem, the system estimates current mastery:

```text
mastery_{u,s} = sigma(a_{u,s})
```

Weak skill coverage is the weighted average of non-mastery:

```text
weak_skill_coverage =
    sum_{s in S_p}(w_{p,s} * (1 - mastery_{u,s}))
    / sum_{s in S_p}(w_{p,s})
```

Problems that exercise weaker skills receive a larger value.

### Uncertainty reduction

The recommender also prefers problems that touch uncertain skills:

```text
uncertainty_reduction =
    sum_{s in S_p}(w_{p,s} * q_{u,s})
    / sum_{s in S_p}(w_{p,s})
```

This favors problems that can teach the system more about the user's current
ability.

### Novelty

The novelty term is based on historical attempts for the problem:

```text
novelty = 1 - clamp(historical_attempts / 50, 0, 0.8)
```

This gives newer or less-attempted problems a higher novelty score, while still
leaving frequently attempted problems with a minimum novelty contribution of
`0.2`.

### Frustration risk

If the predicted solve probability is below `0.45`, the system applies a
frustration penalty:

```text
frustration_risk = clamp((0.45 - P_hat) / 0.45, 0, 1)
```

If the predicted solve probability is at least `0.45`, the frustration risk is:

```text
frustration_risk = 0
```

### Final recommendation score

The final score is:

```text
score =
      0.45 * challenge_fit
    + 0.25 * weak_skill_coverage
    + 0.20 * uncertainty_reduction
    + 0.10 * novelty
    - 0.20 * frustration_risk
```

Candidates are sorted by descending recommendation score. If two candidates
have equal scores, the system breaks ties by higher predicted solve
probability.

## Worked Update Example

Suppose a user attempts a problem with:

```text
d_p = 0.40
g_u = 0.05
eta_u = 0.08
eta_p = 0.05
```

The problem has two skills:

```text
graphs: 0.70
dfs:    0.30
```

The user's current skill abilities are:

```text
a_{u,graphs} = 0.10
a_{u,dfs}    = -0.20
```

The weighted ability is:

```text
A_{u,p} = 0.70 * 0.10 + 0.30 * (-0.20)
        = 0.07 - 0.06
        = 0.01
```

Adding global ability:

```text
theta_{u,p} = 0.01 + 0.05 = 0.06
```

The predicted solve probability is:

```text
P_hat = sigma(0.06 - 0.40)
      = sigma(-0.34)
      approximately 0.416
```

If the user solves the problem on the first attempt, the observed credit is:

```text
c = 1.00
```

The error is:

```text
e = 1.00 - 0.416 = 0.584
```

Skill updates:

```text
Delta a_{u,graphs} = 0.08 * 0.70 * 0.584 = 0.0327
Delta a_{u,dfs}    = 0.08 * 0.30 * 0.584 = 0.0140
```

New skill abilities:

```text
a'_{u,graphs} = 0.1327
a'_{u,dfs}    = -0.1860
```

Global ability update:

```text
g'_u = 0.05 + 0.03 * 0.584 = 0.0675
```

Problem difficulty update:

```text
Delta d_p = -0.05 * 0.584 = -0.0292
d'_p = 0.40 - 0.0292 = 0.3708
```

The model therefore concludes that the user is stronger in the relevant skills
than previously estimated, while the problem may be slightly easier than
previously estimated.

## Assumptions and Limitations

The current model assumes that skill weights are meaningful and reasonably
normalized. The prediction equation uses the raw weighted sum, so weights that
do not sum near `1.0` can scale the effective ability unexpectedly.

The model updates problem difficulty from individual submissions. This is
simple and online, but it means early submissions can move difficulty before a
large population of evidence exists.

The uncertainty fields are operational confidence scores, not formal posterior
variances. They decay with practice but do not currently increase after
surprising outcomes.

The constructor contains a `decay_lambda` parameter, but the current rating
update equations do not use it. Temporal forgetting or inactivity decay could
be added later using that parameter, but it is not part of the active model.

The model does not currently persist every mathematical intermediate in the
database. For example, predicted probability and error are returned by the
rating update, but the current state tables mainly store updated abilities,
difficulties, uncertainties, counters, and timestamps.

