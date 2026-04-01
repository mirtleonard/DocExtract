use strict;
use warnings;

use Test::More;

use lib 'lib';

use DocExtract::AlgoRecommender::RatingService;

{
    package Local::RatingDBH;

    sub new {
        my ($class) = @_;

        return bless {
            in_txn => 0,
            committed => 0,
            rolled_back => 0,
            problem_rating_state => {
                1001 => {
                    problem_id       => 1001,
                    difficulty       => 0.30,
                    uncertainty      => 1,
                    attempts         => 2,
                    solves           => 1,
                    first_try_solves => 1,
                },
            },
            problem_skills => {
                1001 => [
                    { skill_id => 'graphs', weight => 0.6 },
                    { skill_id => 'dfs',    weight => 0.4 },
                ],
            },
            user_problem_state => {
                '42:1001' => {
                    user_id         => 42,
                    problem_id      => 1001,
                    attempts        => 0,
                    solved          => 0,
                    first_solved_at => undef,
                    last_attempt_at => undef,
                },
            },
            user_skill_state => {
                '42:graphs' => {
                    user_id          => 42,
                    skill_id         => 'graphs',
                    ability          => 0.20,
                    uncertainty      => 1,
                    attempts         => 3,
                    solves           => 1,
                    last_practiced_at => undef,
                },
            },
            user_global_state => {
                42 => {
                    user_id        => 42,
                    global_ability => 0.10,
                    uncertainty    => 1,
                    updated_at     => undef,
                },
            },
        }, $class;
    }

    sub begin_work {
        my ($self) = @_;
        $self->{in_txn} = 1;
        return 1;
    }

    sub commit {
        my ($self) = @_;
        $self->{committed}++;
        $self->{in_txn} = 0;
        return 1;
    }

    sub rollback {
        my ($self) = @_;
        $self->{rolled_back}++;
        $self->{in_txn} = 0;
        return 1;
    }

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

        die "Unhandled selectrow_hashref query: $sql";
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
                my $row = $self->{user_skill_state}{"$user_id:$skill_id"};
                push @rows, { %{$row} } if $row;
            }
            return \@rows;
        }

        die "Unhandled selectall_arrayref query: $sql";
    }

    sub do {
        my ($self, $sql, $attr, @bind) = @_;

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

        die "Unhandled do query: $sql";
    }
}

my $dbh = Local::RatingDBH->new();
my $rating = DocExtract::AlgoRecommender::RatingService->new(
    dbh       => $dbh,
    user_k    => 0.08,
    problem_k => 0.05,
);

my $result = $rating->record_submission(
    user_id    => 42,
    problem_id => 1001,
    submission => {
        verdict        => 'accepted',
        tests_passed   => 20,
        tests_total    => 20,
        hint_used      => 0,
        editorial_used => 0,
        created_at     => '2026-04-01T12:00:00Z',
    },
);

is($dbh->{committed}, 1, 'record_submission commits transaction');
is($dbh->{rolled_back}, 0, 'record_submission does not roll back successful transaction');
is($result->{solved}, 1, 'accepted submission counts as solved');
cmp_ok($result->{predicted}, '>', 0, 'result returns predicted probability');
cmp_ok($dbh->{user_skill_state}{'42:graphs'}{ability}, '>', 0.20, 'primary skill ability increases after solve');
ok(exists $dbh->{user_skill_state}{'42:dfs'}, 'secondary skill state is created on first interaction');
is($dbh->{user_skill_state}{'42:graphs'}{attempts}, 4, 'existing skill attempts increment');
is($dbh->{user_skill_state}{'42:dfs'}{attempts}, 1, 'new skill state starts with first attempt');
cmp_ok($dbh->{problem_rating_state}{1001}{difficulty}, '<', 0.30, 'problem difficulty is lowered after successful solve');
is($dbh->{problem_rating_state}{1001}{attempts}, 3, 'problem attempts increment');
is($dbh->{problem_rating_state}{1001}{solves}, 2, 'problem solves increment');
is($dbh->{problem_rating_state}{1001}{first_try_solves}, 2, 'first try solve increments for first successful attempt');
is($dbh->{user_problem_state}{'42:1001'}{solved}, 1, 'user problem state is marked solved');
is($dbh->{user_problem_state}{'42:1001'}{first_solved_at}, '2026-04-01T12:00:00Z', 'first solve timestamp is captured');
cmp_ok($dbh->{user_global_state}{42}{global_ability}, '>', 0.10, 'global ability increases after over-performing');

done_testing;
