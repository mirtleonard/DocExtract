use strict;
use warnings;

use Test::More;
use lib 'lib';

use DocExtract::AlgoRecommender::RatingService;

# -------------------------------------------------------------------
# 1. Provide an In-Memory Database (Mock) for E2E
# -------------------------------------------------------------------
{
    package Local::E2EDBH;

    sub new {
        my ($class) = @_;
        return bless {
            in_txn => 0,
            problem_rating_state => {
                # Problem 1: Easy graph problem
                1 => { problem_id => 1, difficulty => 0.1, uncertainty => 0.5, attempts => 10, solves => 5, first_try_solves => 3 },
                # Problem 2: Medium array problem
                2 => { problem_id => 2, difficulty => 0.5, uncertainty => 0.5, attempts => 10, solves => 2, first_try_solves => 1 },
                # Problem 3: Hard graph & DFS problem
                3 => { problem_id => 3, difficulty => 1.2, uncertainty => 0.5, attempts => 10, solves => 0, first_try_solves => 0 },
            },
            problem_skills => {
                1 => [ { skill_id => 'graphs', weight => 1.0 } ],
                2 => [ { skill_id => 'arrays', weight => 1.0 } ],
                3 => [ { skill_id => 'graphs', weight => 0.6 }, { skill_id => 'dfs', weight => 0.4 } ],
            },
            user_problem_state => {},
            user_skill_state => {},
            user_global_state => {},
        }, $class;
    }

    sub begin_work { $_[0]->{in_txn} = 1; return 1; }
    sub commit     { $_[0]->{in_txn} = 0; return 1; }
    sub rollback   { $_[0]->{in_txn} = 0; return 1; }

    sub selectrow_hashref {
        my ($self, $sql, $attr, @bind) = @_;

        if ($sql =~ /from problem_rating_state/) {
            my $row = $self->{problem_rating_state}{$bind[0]};
            return $row ? { %{$row} } : undef;
        }
        if ($sql =~ /from user_problem_state/) {
            my $row = $self->{user_problem_state}{"$bind[0]:$bind[1]"};
            return $row ? { %{$row} } : undef;
        }
        if ($sql =~ /from user_global_state/) {
            my $row = $self->{user_global_state}{$bind[0]};
            return $row ? { %{$row} } : undef;
        }
        die "Unhandled selectrow_hashref: $sql";
    }

    sub selectall_arrayref {
        my ($self, $sql, $attr, @bind) = @_;

        if ($sql =~ /from problem_skills/) {
            my $rows = $self->{problem_skills}{$bind[0]} || [];
            return [ map { +{ %$_ } } @{$rows} ];
        }
        if ($sql =~ /from user_skill_state/) {
            my $user_id = shift @bind;
            my @rows;
            for my $skill_id (@bind) {
                if (my $row = $self->{user_skill_state}{"$user_id:$skill_id"}) {
                    push @rows, { %{$row} };
                }
            }
            return \@rows;
        }
        die "Unhandled selectall_arrayref: $sql";
    }

    sub do {
        my ($self, $sql, $attr, @bind) = @_;

        if ($sql =~ /insert into user_skill_state/) {
            my ($user_id, $skill_id, $ability, $uncertainty, $attempts, $solves, $last_practiced_at) = @bind;
            $self->{user_skill_state}{"$user_id:$skill_id"} = {
                user_id => $user_id, skill_id => $skill_id, ability => $ability,
                uncertainty => $uncertainty, attempts => $attempts, solves => $solves,
                last_practiced_at => $last_practiced_at,
            };
            return 1;
        }
        if ($sql =~ /insert into user_global_state/) {
            my ($user_id, $global_ability, $uncertainty, $updated_at) = @bind;
            $self->{user_global_state}{$user_id} = {
                user_id => $user_id, global_ability => $global_ability,
                uncertainty => $uncertainty, updated_at => $updated_at,
            };
            return 1;
        }
        if ($sql =~ /insert into problem_rating_state/) {
            my ($problem_id, $difficulty, $uncertainty, $attempts, $solves, $first_try) = @bind;
            $self->{problem_rating_state}{$problem_id} = {
                problem_id => $problem_id, difficulty => $difficulty,
                uncertainty => $uncertainty, attempts => $attempts, solves => $solves, first_try_solves => $first_try,
            };
            return 1;
        }
        if ($sql =~ /insert into user_problem_state/) {
            my ($user_id, $problem_id, $attempts, $solved, $first_solved_at, $last_attempt_at) = @bind;
            $self->{user_problem_state}{"$user_id:$problem_id"} = {
                user_id => $user_id, problem_id => $problem_id, attempts => $attempts,
                solved => $solved, first_solved_at => $first_solved_at, last_attempt_at => $last_attempt_at,
            };
            return 1;
        }
        die "Unhandled do query: $sql";
    }
}

# -------------------------------------------------------------------
# 2. Setup The Test Environment
# -------------------------------------------------------------------
my $dbh = Local::E2EDBH->new();
my $rating_service = DocExtract::AlgoRecommender::RatingService->new(
    dbh       => $dbh,
    user_k    => 0.1,  # slightly higher K to see skill movements faster
    problem_k => 0.05,
);

my $new_user_id = 99;

# Helper to fetch current skill ability
sub get_skill {
    my ($skill) = @_;
    return $dbh->{user_skill_state}{"$new_user_id:$skill"}{ability} // 0;
}

# Helper to fetch global ability
sub get_global {
    return $dbh->{user_global_state}{$new_user_id}{global_ability} // 0;
}

# -------------------------------------------------------------------
# 3. Simulate The User Journey
# -------------------------------------------------------------------

# STEP 1: New user fails "Problem 1" (Easy Graph Problem)
my $res1 = $rating_service->record_submission(
    user_id    => $new_user_id,
    problem_id => 1,
    submission => { verdict => 'wrong_answer', tests_passed => 2, tests_total => 10, created_at => '2026-04-01T10:00:00Z' },
);

ok($res1, "Failed submission recorded successfully");
is($res1->{solved}, 0, "Not marked as solved");
cmp_ok(get_skill('graphs'), '<', 0, "User graph skill drops below zero after a failure");
cmp_ok(get_global(), '<', 0, "General global ability also drops slightly");
my $skill_after_fail = get_skill('graphs');


# STEP 2: User tries "Problem 1" again and gets it right!
my $res2 = $rating_service->record_submission(
    user_id    => $new_user_id,
    problem_id => 1,
    submission => { verdict => 'accepted', created_at => '2026-04-01T10:15:00Z' },
);

is($res2->{solved}, 1, "Problem solved on second attempt");
cmp_ok(get_skill('graphs'), '>', $skill_after_fail, "Graph skill recovers after successful solve");
ok($res2->{observed} < 1.0, "They don't get 100% credit because it was their second attempt");


# STEP 3: User solves "Problem 2" (Medium Arrays) perfect on the first try
my $res3 = $rating_service->record_submission(
    user_id    => $new_user_id,
    problem_id => 2,
    submission => { verdict => 'accepted', created_at => '2026-04-01T10:30:00Z' },
);

is($res3->{solved}, 1, "Medium array problem solved");
is($res3->{observed}, 1.0, "Perfect score for first try solve");
cmp_ok(get_skill('arrays'), '>', 0, "Array skill was created and immediately boosted above zero");
my $array_skill = get_skill('arrays');

my $graph_skill_before_hard = get_skill('graphs');

# STEP 4: User tackles "Problem 3" (Hard Graph & DFS) and solves it!
my $res4 = $rating_service->record_submission(
    user_id    => $new_user_id,
    problem_id => 3,
    submission => { verdict => 'accepted', created_at => '2026-04-01T11:00:00Z' },
);

my $final_graph_skill = get_skill('graphs');
my $final_dfs_skill   = get_skill('dfs');

cmp_ok($final_graph_skill, '>', $graph_skill_before_hard, "Graph skill gains a massive boost from solving a hard problem");
cmp_ok($final_dfs_skill, '>', 0, "DFS skill created and boosted");
cmp_ok(get_global(), '>', 0, "Global ability is now strongly positive after an impressive hard solve");

# Inspect the database records
is($dbh->{user_problem_state}{"$new_user_id:3"}{attempts}, 1, "Recorded 1 attempt on the hard problem");
is($dbh->{user_problem_state}{"$new_user_id:1"}{attempts}, 2, "Recorded 2 attempts on the easy problem");

done_testing;
