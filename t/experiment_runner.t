use strict;
use warnings;

use File::Temp qw(tempfile);
use JSON::PP qw(decode_json);
use Test::More;

use lib 'lib';

use DocExtract::AlgoRecommender::ExperimentRunner;
use DocExtract::AlgoRecommender::RatingService;
use DocExtract::AlgoRecommender::RecommendationService;

{
    package Local::RunnerDBH;

    sub new {
        my ($class) = @_;

        return bless {
            next_submission_id => 1,
            skills => [
                { id => 2,  code => 'arrays',         name => 'Arrays' },
                { id => 6,  code => 'hashing',        name => 'Hash Maps / Hash Sets' },
                { id => 8,  code => 'sliding_window', name => 'Sliding Window' },
                { id => 12, code => 'graphs',         name => 'Graph Theory' },
                { id => 13, code => 'bfs_dfs',        name => 'BFS/DFS Search' },
                { id => 14, code => 'dp',             name => 'Dynamic Programming' },
            ],
            problems => {
                6  => { id => 6,  title => 'Two Sum' },
                14 => { id => 14, title => 'Longest Substring Without Repeats' },
                23 => { id => 23, title => 'Number of Islands' },
                28 => { id => 28, title => 'Coin Change' },
            },
            problem_skills => {
                6  => [ { problem_id => 6,  skill_id => 6,  weight => 0.8 }, { problem_id => 6,  skill_id => 2,  weight => 0.2 } ],
                14 => [ { problem_id => 14, skill_id => 8,  weight => 0.6 }, { problem_id => 14, skill_id => 6,  weight => 0.4 } ],
                23 => [ { problem_id => 23, skill_id => 12, weight => 0.3 }, { problem_id => 23, skill_id => 13, weight => 0.7 } ],
                28 => [ { problem_id => 28, skill_id => 14, weight => 1.0 } ],
            },
            problem_rating_state => {
                6  => { problem_id => 6,  difficulty => -0.5, uncertainty => 0.6, attempts => 12, solves => 8, first_try_solves => 4 },
                14 => { problem_id => 14, difficulty => 0.5,  uncertainty => 0.8, attempts => 10, solves => 4, first_try_solves => 2 },
                23 => { problem_id => 23, difficulty => 1.2,  uncertainty => 0.9, attempts => 7,  solves => 2, first_try_solves => 1 },
                28 => { problem_id => 28, difficulty => 1.8,  uncertainty => 0.9, attempts => 6,  solves => 1, first_try_solves => 0 },
            },
            user_skill_state => {},
            user_global_state => {},
            user_problem_state => {},
            submissions => [],
        }, $class;
    }

    sub begin_work { return 1; }
    sub commit     { return 1; }
    sub rollback   { return 1; }

    sub selectall_arrayref {
        my ($self, $sql, $attr, @bind) = @_;

        if ($sql =~ /from skills/) {
            return [ map { +{ %$_ } } @{ $self->{skills} } ];
        }

        if ($sql =~ /select id, title\s+from problems/) {
            return [ map { +{ %{ $self->{problems}{$_} } } } sort { $a <=> $b } keys %{ $self->{problems} } ];
        }

        if ($sql =~ /from user_skill_state/ && $sql =~ /skill_id in/) {
            my $user_id = shift @bind;
            my @rows;
            for my $skill_id (@bind) {
                my $row = $self->{user_skill_state}{"$user_id:$skill_id"};
                push @rows, { %{$row} } if $row;
            }
            return \@rows;
        }

        if ($sql =~ /from user_skill_state/) {
            my $user_id = $bind[0];
            my @rows = map { +{ %{ $self->{user_skill_state}{$_} } } }
                sort keys %{ $self->{user_skill_state} };
            @rows = grep { $_->{user_id} == $user_id } @rows;
            return \@rows;
        }

        if ($sql =~ /from problem_skills/ && @bind == 1) {
            my $rows = $self->{problem_skills}{ $bind[0] } || [];
            return [ map { +{ %$_ } } @{$rows} ];
        }

        if ($sql =~ /from problem_skills/) {
            my @rows;
            for my $problem_id (@bind) {
                push @rows, map { +{ %$_ } } @{ $self->{problem_skills}{$problem_id} || [] };
            }
            return \@rows;
        }

        if ($sql =~ /from problems p/) {
            my ($user_id, @rest) = @bind;
            my $limit = pop @rest;
            my $cutoff = @rest ? $rest[0] : undef;

            my @rows;
            for my $problem_id (sort { $self->{problem_rating_state}{$b}{attempts} <=> $self->{problem_rating_state}{$a}{attempts} || $a <=> $b } keys %{ $self->{problems} }) {
                my $ups = $self->{user_problem_state}{"$user_id:$problem_id"};
                next if $ups && $ups->{solved};
                if (defined $cutoff && $ups && defined $ups->{last_attempt_at}) {
                    next if $ups->{last_attempt_at} ge $cutoff;
                }

                push @rows, {
                    problem_id          => $problem_id,
                    title               => $self->{problems}{$problem_id}{title},
                    difficulty          => $self->{problem_rating_state}{$problem_id}{difficulty},
                    historical_attempts => $self->{problem_rating_state}{$problem_id}{attempts},
                };
            }

            if (@rows > $limit) {
                splice @rows, $limit;
            }

            return \@rows;
        }

        die "Unhandled selectall_arrayref query: $sql";
    }

    sub selectrow_array {
        my ($self, $sql, $attr, @bind) = @_;

        if ($sql =~ /from user_global_state/) {
            my $row = $self->{user_global_state}{ $bind[0] };
            return $row ? $row->{global_ability} : 0;
        }

        die "Unhandled selectrow_array query: $sql";
    }

    sub selectrow_hashref {
        my ($self, $sql, $attr, @bind) = @_;

        if ($sql =~ /from problem_rating_state/) {
            my $row = $self->{problem_rating_state}{ $bind[0] };
            return $row ? { %{$row} } : undef;
        }

        if ($sql =~ /from user_problem_state/) {
            my $row = $self->{user_problem_state}{"$bind[0]:$bind[1]"};
            return $row ? { %{$row} } : undef;
        }

        if ($sql =~ /from user_global_state/) {
            my $row = $self->{user_global_state}{ $bind[0] };
            return $row ? { %{$row} } : undef;
        }

        die "Unhandled selectrow_hashref query: $sql";
    }

    sub do {
        my ($self, $sql, $attr, @bind) = @_;

        if ($sql =~ /^delete from (\w+) where user_id between \? and \?$/) {
            my ($table, $min, $max) = ($1, @bind);
            if ($table eq 'submissions') {
                my @kept = grep { $_->{user_id} < $min || $_->{user_id} > $max } @{ $self->{submissions} };
                $self->{submissions} = \@kept;
                return 1;
            }
            my $store = $self->{$table};
            for my $key (keys %{$store}) {
                my $user_id = $key =~ /:/ ? (split /:/, $key)[0] : $key;
                delete $store->{$key} if $user_id >= $min && $user_id <= $max;
            }
            return 1;
        }

        if ($sql =~ /insert into submissions/) {
            push @{ $self->{submissions} }, {
                id             => $self->{next_submission_id}++,
                user_id        => $bind[0],
                problem_id     => $bind[1],
                verdict        => $bind[2],
                score          => $bind[3],
                runtime_ms     => $bind[4],
                memory_kb      => $bind[5],
                tests_passed   => $bind[6],
                tests_total    => $bind[7],
                hint_used      => $bind[8],
                editorial_used => $bind[9],
                created_at     => $bind[10],
            };
            return 1;
        }

        if ($sql =~ /insert into user_global_state/) {
            my ($user_id, $global_ability, $uncertainty, $updated_at) = @bind;
            $self->{user_global_state}{$user_id} = {
                user_id        => $user_id,
                global_ability => $global_ability,
                uncertainty    => $uncertainty,
                updated_at     => $updated_at,
            };
            return 1;
        }

        if ($sql =~ /insert into user_skill_state/) {
            my ($user_id, $skill_id, $ability, $uncertainty, $attempts, $solves, $last_practiced_at) = @bind;
            $self->{user_skill_state}{"$user_id:$skill_id"} = {
                user_id          => $user_id,
                skill_id         => $skill_id,
                ability          => $ability,
                uncertainty      => $uncertainty,
                attempts         => $attempts,
                solves           => $solves,
                last_practiced_at => $last_practiced_at,
            };
            return 1;
        }

        if ($sql =~ /insert into user_problem_state/) {
            my ($user_id, $problem_id, $attempts, $solved, $first_solved_at, $last_attempt_at) = @bind;
            $self->{user_problem_state}{"$user_id:$problem_id"} = {
                user_id         => $user_id,
                problem_id      => $problem_id,
                attempts        => $attempts,
                solved          => $solved,
                first_solved_at => $first_solved_at,
                last_attempt_at => $last_attempt_at,
            };
            return 1;
        }

        if ($sql =~ /insert into problem_rating_state/) {
            my ($problem_id, $difficulty, $uncertainty, $attempts, $solves, $first_try_solves) = @bind;
            $self->{problem_rating_state}{$problem_id} = {
                problem_id       => $problem_id,
                difficulty       => $difficulty,
                uncertainty      => $uncertainty,
                attempts         => $attempts,
                solves           => $solves,
                first_try_solves => $first_try_solves,
            };
            return 1;
        }

        die "Unhandled do query: $sql";
    }
}

my $dbh = Local::RunnerDBH->new();
my $rating = DocExtract::AlgoRecommender::RatingService->new(
    dbh       => $dbh,
    user_k    => 0.08,
    problem_k => 0.05,
);
my $recommendation = DocExtract::AlgoRecommender::RecommendationService->new(
    dbh                          => $dbh,
    rating_service               => $rating,
    recent_attempt_cooldown_days => 0,
);

my $personas = [
    {
        user_id => 9101,
        slug => 'hashing-learner',
        name => 'Hashing Learner',
        description => 'Learner who improves from easy hashing into sliding window.',
        initial_global_ability => -0.10,
        initial_skills => [
            { skill_code => 'arrays', ability => 0.10, uncertainty => 0.90, attempts => 4, solves => 3 },
            { skill_code => 'hashing', ability => -0.15, uncertainty => 0.95, attempts => 3, solves => 1 },
        ],
        pre_solved_problem_ids => [],
        submissions => [
            { problem_id => 6, verdict => 'accepted', created_at => '2026-05-01T09:00:00Z' },
            { problem_id => 14, verdict => 'accepted', created_at => '2026-05-01T09:18:00Z' },
        ],
    },
    {
        user_id => 9102,
        slug => 'graph-vs-dp',
        name => 'Graph vs DP Specialist',
        description => 'Strong on graphs and weaker on dynamic programming.',
        initial_global_ability => 0.35,
        initial_skills => [
            { skill_code => 'graphs', ability => 0.80, uncertainty => 0.35, attempts => 14, solves => 11 },
            { skill_code => 'bfs_dfs', ability => 0.70, uncertainty => 0.40, attempts => 13, solves => 10 },
            { skill_code => 'dp', ability => -0.25, uncertainty => 0.90, attempts => 4, solves => 1 },
        ],
        pre_solved_problem_ids => [23],
        submissions => [
            { problem_id => 28, verdict => 'wrong_answer', tests_passed => 3, tests_total => 10, created_at => '2026-05-01T09:05:00Z' },
            { problem_id => 23, verdict => 'accepted', created_at => '2026-05-01T09:20:00Z' },
        ],
    },
];

my ($fh, $json_path) = tempfile(SUFFIX => '.json');
close $fh;

my $runner = DocExtract::AlgoRecommender::ExperimentRunner->new(
    dbh                    => $dbh,
    personas               => $personas,
    rating_service         => $rating,
    recommendation_service => $recommendation,
    top_n                  => 3,
    export_path            => $json_path,
);

my $result = $runner->run(
    run_label => 'test-run',
);

is($result->{persona_count}, 2, 'runner processes both personas');
is(scalar @{ $result->{personas} }, 2, 'runner returns results for each persona');
ok(@{ $dbh->{submissions} } >= 4, 'runner persisted simulated submissions');

my $first = $result->{personas}[0];
cmp_ok($first->{after}{global_ability}, '>', $first->{before}{global_ability}, 'successful learner gains global ability');
ok(@{ $first->{before}{recommendations} } > 0, 'before snapshot includes recommendations');
ok(@{ $first->{after}{recommendations} } > 0, 'after snapshot includes recommendations');
isnt(
    join(',', map { $_->{problem_id} } @{ $first->{before}{recommendations} }),
    join(',', map { $_->{problem_id} } @{ $first->{after}{recommendations} }),
    'recommendations change after replayed submissions',
);

my $second = $result->{personas}[1];
is($dbh->{user_problem_state}{'9102:28'}{solved}, 0, 'failed DP attempt remains unsolved in user problem state');
cmp_ok($dbh->{user_skill_state}{'9102:12'}{ability}, '>', 0.80, 'successful follow-up graph solve still boosts graph ability');

open my $json_fh, '<:encoding(UTF-8)', $json_path or die "cannot open $json_path: $!";
local $/;
my $json = <$json_fh>;
close $json_fh;

my $decoded = decode_json($json);
is($decoded->{run_label}, 'test-run', 'runner writes structured JSON report');
is($decoded->{top_n}, 3, 'JSON report preserves top_n');
like($runner->format_report($result), qr/Hashing Learner/, 'formatted console report includes persona names');

unlink $json_path;

done_testing;
