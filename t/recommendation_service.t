use strict;
use warnings;

use Test::More;

use lib 'lib';

use DocExtract::AlgoRecommender::RatingService;
use DocExtract::AlgoRecommender::RecommendationService;

{
    package Local::RecommendationDBH;

    sub new {
        my ($class) = @_;

        return bless {
            user_skills => {
                7 => [
                    {
                        skill_id         => 'graphs',
                        ability          => -0.2,
                        uncertainty      => 0.9,
                        attempts         => 4,
                        solves           => 1,
                        last_practiced_at => '2026-03-28T09:00:00Z',
                    },
                    {
                        skill_id         => 'arrays',
                        ability          => 0.7,
                        uncertainty      => 0.2,
                        attempts         => 10,
                        solves           => 8,
                        last_practiced_at => '2026-03-30T09:00:00Z',
                    },
                ],
            },
            global_ability => {
                7 => 0.05,
            },
            candidate_problems => [
                {
                    problem_id          => 11,
                    title               => 'Graph Traversal',
                    difficulty          => 0.15,
                    historical_attempts => 8,
                },
                {
                    problem_id          => 12,
                    title               => 'Array Warmup',
                    difficulty          => 0.05,
                    historical_attempts => 35,
                },
            ],
            problem_skills => {
                11 => [
                    { problem_id => 11, skill_id => 'graphs', weight => 0.7 },
                    { problem_id => 11, skill_id => 'bfs',    weight => 0.3 },
                ],
                12 => [
                    { problem_id => 12, skill_id => 'arrays', weight => 1.0 },
                ],
            },
        }, $class;
    }

    sub selectall_arrayref {
        my ($self, $sql, $attr, @bind) = @_;

        if ($sql =~ /from user_skill_state/) {
            my $rows = $self->{user_skills}{$bind[0]} || [];
            return [ map { +{ %$_ } } @{$rows} ];
        }

        if ($sql =~ /from problems p/) {
            return [ map { +{ %$_ } } @{$self->{candidate_problems}} ];
        }

        if ($sql =~ /from problem_skills/) {
            my @rows;
            for my $problem_id (@bind) {
                push @rows, map { +{ %$_ } } @{ $self->{problem_skills}{$problem_id} || [] };
            }
            return \@rows;
        }

        die "Unhandled selectall_arrayref query: $sql";
    }

    sub selectrow_array {
        my ($self, $sql, $attr, @bind) = @_;

        if ($sql =~ /from user_global_state/) {
            return $self->{global_ability}{$bind[0]} // 0;
        }

        die "Unhandled selectrow_array query: $sql";
    }
}

my $rating = DocExtract::AlgoRecommender::RatingService->new();
my $recommendation = DocExtract::AlgoRecommender::RecommendationService->new(
    target_probability => 0.72,
    rating_service     => $rating,
);

my $ranked = $recommendation->rank_candidates(
    user_skills => {
        arrays => { ability => 0.8, uncertainty => 0.2 },
        graphs => { ability => -0.2, uncertainty => 0.8 },
        bfs    => { ability => -0.1, uncertainty => 0.9 },
    },
    problems => [
        {
            problem_id          => 1,
            title               => 'Array Warmup',
            difficulty          => 0.1,
            historical_attempts => 40,
            skills              => [
                { skill_id => 'arrays', weight => 1.0 },
            ],
        },
        {
            problem_id          => 2,
            title               => 'Graph Practice',
            difficulty          => 0.2,
            historical_attempts => 8,
            skills              => [
                { skill_id => 'graphs', weight => 0.6 },
                { skill_id => 'bfs',    weight => 0.4 },
            ],
        },
    ],
);

is($ranked->[0]{problem_id}, 2, 'rank_candidates prioritizes weaker and more uncertain skills');
cmp_ok($ranked->[0]{recommendation_score}, '>', $ranked->[1]{recommendation_score}, 'ranked results are sorted by descending recommendation score');

my $too_hard = $recommendation->score_candidate(
    user_skills => {
        graphs => { ability => -0.5, uncertainty => 0.9 },
    },
    problem => {
        problem_id          => 20,
        difficulty          => 1.2,
        historical_attempts => 5,
        skills              => [
            { skill_id => 'graphs', weight => 1.0 },
        ],
    },
);

my $well_matched = $recommendation->score_candidate(
    user_skills => {
        graphs => { ability => -0.1, uncertainty => 0.9 },
    },
    problem => {
        problem_id          => 21,
        difficulty          => 0.2,
        historical_attempts => 5,
        skills              => [
            { skill_id => 'graphs', weight => 1.0 },
        ],
    },
);

cmp_ok($too_hard->{frustration_risk}, '>', 0, 'too-hard problem carries frustration risk');
cmp_ok($well_matched->{recommendation_score}, '>', $too_hard->{recommendation_score}, 'well-matched problem outranks too-hard problem');

my $dbh = Local::RecommendationDBH->new();
my $db_recommendation = DocExtract::AlgoRecommender::RecommendationService->new(
    dbh             => $dbh,
    candidate_limit => 10,
    rating_service  => $rating,
);

my $recommended = $db_recommendation->recommend_for_user(
    user_id => 7,
    limit   => 1,
);

is(scalar @{$recommended}, 1, 'recommend_for_user applies requested limit');
is($recommended->[0]{problem_id}, 11, 'recommend_for_user loads DB-backed candidates and ranks graph practice first');

done_testing;
