use strict;
use warnings;

use Test::More;

use lib 'lib';

use DocExtract::AlgoRecommender::RatingService;

my $rating = DocExtract::AlgoRecommender::RatingService->new(
    user_k          => 0.08,
    problem_k       => 0.05,
    min_uncertainty => 0.20,
);

is(
    $rating->compute_observed_credit(
        submission => {
            verdict        => 'accepted',
            hint_used      => 0,
            editorial_used => 0,
        },
        prior_attempts => 0,
    ),
    1,
    'first try accepted gets full credit',
);

is(
    $rating->compute_observed_credit(
        submission => {
            verdict        => 'accepted',
            hint_used      => 1,
            editorial_used => 1,
        },
        prior_attempts => 4,
    ),
    0.45,
    'late solve with help is discounted',
);

is(
    $rating->compute_observed_credit(
        submission => {
            verdict        => 'wrong_answer',
            tests_passed   => 5,
            tests_total    => 10,
            hint_used      => 1,
            editorial_used => 0,
        },
        prior_attempts => 2,
    ),
    0.25,
    'partial progress yields bounded partial credit',
);

is(
    $rating->compute_observed_credit(
        submission => {
            verdict        => 'runtime_error',
            tests_passed   => 0,
            tests_total    => 0,
        },
        prior_attempts => 1,
    ),
    0,
    'non-progressing attempt yields zero credit',
);

my $base_probability = $rating->predict_probability(
    abilities => {
        graphs => { ability => 0.4 },
        dfs    => { ability => 0.1 },
    },
    skill_weights => [
        { skill_id => 'graphs', weight => 0.7 },
        { skill_id => 'dfs',    weight => 0.3 },
    ],
    difficulty => 0.2,
);

my $biased_probability = $rating->predict_probability(
    abilities => {
        graphs => { ability => 0.4 },
        dfs    => { ability => 0.1 },
    },
    skill_weights => [
        { skill_id => 'graphs', weight => 0.7 },
        { skill_id => 'dfs',    weight => 0.3 },
    ],
    difficulty  => 0.2,
    global_bias => 0.3,
);

cmp_ok($base_probability, '>', 0.5, 'prediction reflects positive ability');
cmp_ok($biased_probability, '>', $base_probability, 'global ability bias increases solve probability');

my $positive_updates = $rating->compute_skill_updates(
    abilities => {
        graphs => { ability => 0.4 },
        dfs    => { ability => 0.1 },
    },
    skill_weights => [
        { skill_id => 'graphs', weight => 0.7 },
        { skill_id => 'dfs',    weight => 0.3 },
    ],
    difficulty => 0.2,
    observed   => 1,
);

cmp_ok($positive_updates->{user_skill_delta}{graphs}, '>', $positive_updates->{user_skill_delta}{dfs}, 'higher weight gets larger positive update');
cmp_ok($positive_updates->{problem_delta}, '<', 0, 'successful solve lowers difficulty');

my $negative_updates = $rating->compute_skill_updates(
    abilities => {
        graphs => { ability => 0.9 },
    },
    skill_weights => [
        { skill_id => 'graphs', weight => 1.0 },
    ],
    difficulty => -0.1,
    observed   => 0,
);

cmp_ok($negative_updates->{error}, '<', 0, 'failed attempt produces negative error');
cmp_ok($negative_updates->{user_skill_delta}{graphs}, '<', 0, 'failed attempt reduces skill ability');
cmp_ok($negative_updates->{problem_delta}, '>', 0, 'failed attempt raises difficulty');

my $projected = $rating->project_user_skill_state(
    current => {
        ability     => 0.3,
        uncertainty => 0.21,
        attempts    => 4,
        solves      => 1,
    },
    skill_delta  => 0.05,
    solved       => 1,
    attempted_at => '2026-04-01T12:00:00Z',
);

is($projected->{ability}, 0.35, 'projected state applies skill delta');
is($projected->{attempts}, 5, 'projected state increments attempts');
is($projected->{solves}, 2, 'projected state increments solves');
is($projected->{uncertainty}, 0.2037, 'projected state decays uncertainty');
is($projected->{last_practiced_at}, '2026-04-01T12:00:00Z', 'projected state stores timestamp');

my $min_uncertainty_projected = $rating->project_user_skill_state(
    current => {
        ability     => 0,
        uncertainty => 0.05,
        attempts    => 0,
        solves      => 0,
    },
    skill_delta  => 0,
    solved       => 0,
    attempted_at => '2026-04-01T12:00:00Z',
);

is($min_uncertainty_projected->{uncertainty}, 0.20, 'uncertainty is clamped to configured floor');

done_testing;
