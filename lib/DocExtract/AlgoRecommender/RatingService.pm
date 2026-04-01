package DocExtract::AlgoRecommender::RatingService;

use strict;
use warnings;

use Carp qw(croak);

use DocExtract::AlgoRecommender::Util qw(ability_to_mastery clamp sigmoid weighted_sum);

sub new {
    my ($class, %args) = @_;

    my $self = bless {
        dbh               => $args{dbh},
        user_k            => $args{user_k} // 0.08,
        problem_k         => $args{problem_k} // 0.05,
        baseline_ability  => $args{baseline_ability} // 0,
        baseline_diff     => $args{baseline_diff} // 0,
        decay_lambda      => $args{decay_lambda} // 0.015,
        min_uncertainty   => $args{min_uncertainty} // 0.15,
        uncertainty_decay => $args{uncertainty_decay} // 0.97,
    }, $class;

    return $self;
}

sub predict_probability {
    my ($self, %args) = @_;

    my $abilities     = $args{abilities}     || {};
    my $skill_weights = $args{skill_weights} || [];
    my $difficulty    = defined $args{difficulty} ? $args{difficulty} : $self->{baseline_diff};
    my $global_bias   = $args{global_bias} // 0;

    my $theta = weighted_sum($abilities, $skill_weights) + $global_bias;

    return sigmoid($theta - $difficulty);
}

sub compute_observed_credit {
    my ($self, %args) = @_;

    my $submission      = $args{submission} || {};
    my $prior_attempts  = $args{prior_attempts} // 0;
    my $verdict         = lc($submission->{verdict} // '');
    my $hint_used       = $submission->{hint_used} ? 1 : 0;
    my $editorial_used  = $submission->{editorial_used} ? 1 : 0;
    my $tests_passed    = $submission->{tests_passed};
    my $tests_total     = $submission->{tests_total};

    if ($verdict eq 'accepted' || $verdict eq 'ac') {
        my $credit = 1.00;
        $credit = 0.85 if $prior_attempts >= 1;
        $credit = 0.70 if $prior_attempts >= 3;
        $credit -= 0.10 if $hint_used;
        $credit -= 0.15 if $editorial_used;
        return clamp($credit, 0.25, 1.00);
    }

    if (defined $tests_passed && defined $tests_total && $tests_total > 0) {
        my $partial = 0.60 * ($tests_passed / $tests_total);
        $partial -= 0.05 if $hint_used;
        $partial -= 0.10 if $editorial_used;
        return clamp($partial, 0.00, 0.60);
    }

    return 0.00;
}

sub compute_skill_updates {
    my ($self, %args) = @_;

    my $abilities     = $args{abilities}     || {};
    my $skill_weights = $args{skill_weights} || [];
    my $difficulty    = defined $args{difficulty} ? $args{difficulty} : $self->{baseline_diff};
    my $observed      = $args{observed};
    my $global_bias   = $args{global_bias} // 0;

    croak 'observed is required' if !defined $observed;

    my $predicted = $self->predict_probability(
        abilities     => $abilities,
        skill_weights => $skill_weights,
        difficulty    => $difficulty,
        global_bias   => $global_bias,
    );

    my $error = $observed - $predicted;
    my %deltas;

    for my $skill (@{$skill_weights}) {
        my $skill_id = $skill->{skill_id};
        my $weight   = $skill->{weight} // 0;
        $deltas{$skill_id} = $self->{user_k} * $weight * $error;
    }

    return {
        predicted        => $predicted,
        error            => $error,
        problem_delta    => -$self->{problem_k} * $error,
        user_skill_delta => \%deltas,
    };
}

sub project_user_skill_state {
    my ($self, %args) = @_;

    my $current     = $args{current} || {};
    my $skill_delta = $args{skill_delta} // 0;
    my $attempted_at = $args{attempted_at};

    my $uncertainty = $current->{uncertainty};
    $uncertainty = 1 if !defined $uncertainty;

    my $updated_uncertainty = clamp(
        $uncertainty * $self->{uncertainty_decay},
        $self->{min_uncertainty},
        1,
    );

    return {
        ability          => ($current->{ability} // $self->{baseline_ability}) + $skill_delta,
        uncertainty      => $updated_uncertainty,
        attempts         => ($current->{attempts} // 0) + 1,
        solves           => ($current->{solves} // 0) + (($args{solved} || 0) ? 1 : 0),
        mastery_prob     => ability_to_mastery(($current->{ability} // $self->{baseline_ability}) + $skill_delta),
        last_practiced_at => $attempted_at,
    };
}

sub record_submission {
    my ($self, %args) = @_;

    my $dbh = $self->{dbh} or croak 'dbh is required for record_submission';
    my $user_id = $args{user_id} or croak 'user_id is required';
    my $problem_id = $args{problem_id} or croak 'problem_id is required';
    my $submission = $args{submission} || {};

    my $result;

    $dbh->begin_work;
    eval {
        my $problem_state = $self->_load_problem_state_for_update($problem_id);
        my $problem_skills = $self->_load_problem_skills($problem_id);
        croak "problem $problem_id has no linked skills" if !@{$problem_skills};

        my $user_problem_state = $self->_load_user_problem_state_for_update($user_id, $problem_id);
        my $user_skill_states = $self->_load_user_skill_states_for_update($user_id, $problem_skills);
        my $user_global_state = $self->_load_user_global_state_for_update($user_id);

        my $observed = $self->compute_observed_credit(
            submission     => $submission,
            prior_attempts => $user_problem_state->{attempts} // 0,
        );

        my $updates = $self->compute_skill_updates(
            abilities     => $user_skill_states,
            skill_weights => $problem_skills,
            difficulty    => $problem_state->{difficulty},
            observed      => $observed,
            global_bias   => $user_global_state->{global_ability},
        );

        my $attempted_at = $submission->{created_at};
        my $solved = $observed >= 0.70 ? 1 : 0;

        for my $skill (@{$problem_skills}) {
            my $skill_id = $skill->{skill_id};
            my $next = $self->project_user_skill_state(
                current      => $user_skill_states->{$skill_id},
                skill_delta  => $updates->{user_skill_delta}{$skill_id},
                solved       => $solved,
                attempted_at => $attempted_at,
            );
            $self->_upsert_user_skill_state($user_id, $skill_id, $next);
        }

        $self->_upsert_user_global_state(
            $user_id,
            $user_global_state->{global_ability} + ($updates->{error} * 0.03),
            $attempted_at,
        );

        $self->_upsert_problem_rating_state(
            problem_id      => $problem_id,
            current         => $problem_state,
            problem_delta   => $updates->{problem_delta},
            solved          => $solved,
            first_try_solve => $solved && (($user_problem_state->{attempts} // 0) == 0),
        );

        $self->_upsert_user_problem_state(
            user_id       => $user_id,
            problem_id    => $problem_id,
            current       => $user_problem_state,
            solved        => $solved,
            attempted_at  => $attempted_at,
        );

        $dbh->commit;
        $result = {
            observed  => $observed,
            predicted => $updates->{predicted},
            error     => $updates->{error},
            solved    => $solved,
        };
        1;
    } or do {
        my $error = $@ || 'rating update failed';
        eval { $dbh->rollback };
        die $error;
    };

    return $result;
}

sub _load_problem_state_for_update {
    my ($self, $problem_id) = @_;

    my $row = $self->{dbh}->selectrow_hashref(
        q{
            select
                problem_id,
                difficulty,
                uncertainty,
                attempts,
                solves,
                first_try_solves
            from problem_rating_state
            where problem_id = ?
            for update
        },
        undef,
        $problem_id,
    );

    return $row if $row;

    return {
        problem_id        => $problem_id,
        difficulty        => $self->{baseline_diff},
        uncertainty       => 1,
        attempts          => 0,
        solves            => 0,
        first_try_solves  => 0,
    };
}

sub _load_problem_skills {
    my ($self, $problem_id) = @_;

    return $self->{dbh}->selectall_arrayref(
        q{
            select skill_id, weight
            from problem_skills
            where problem_id = ?
            order by weight desc, skill_id asc
        },
        { Slice => {} },
        $problem_id,
    );
}

sub _load_user_problem_state_for_update {
    my ($self, $user_id, $problem_id) = @_;

    my $row = $self->{dbh}->selectrow_hashref(
        q{
            select user_id, problem_id, attempts, solved, first_solved_at, last_attempt_at
            from user_problem_state
            where user_id = ? and problem_id = ?
            for update
        },
        undef,
        $user_id,
        $problem_id,
    );

    return $row if $row;

    return {
        user_id         => $user_id,
        problem_id      => $problem_id,
        attempts        => 0,
        solved          => 0,
        first_solved_at => undef,
        last_attempt_at => undef,
    };
}

sub _load_user_skill_states_for_update {
    my ($self, $user_id, $problem_skills) = @_;

    my @skill_ids = map { $_->{skill_id} } @{$problem_skills};
    my $placeholders = join q{, }, ('?') x @skill_ids;

    my $rows = $self->{dbh}->selectall_arrayref(
        qq{
            select user_id, skill_id, ability, uncertainty, attempts, solves, last_practiced_at
            from user_skill_state
            where user_id = ? and skill_id in ($placeholders)
            for update
        },
        { Slice => {} },
        $user_id,
        @skill_ids,
    );

    my %states = map { $_->{skill_id} => $_ } @{$rows};

    for my $skill_id (@skill_ids) {
        next if exists $states{$skill_id};
        $states{$skill_id} = {
            user_id          => $user_id,
            skill_id         => $skill_id,
            ability          => $self->{baseline_ability},
            uncertainty      => 1,
            attempts         => 0,
            solves           => 0,
            last_practiced_at => undef,
        };
    }

    return \%states;
}

sub _load_user_global_state_for_update {
    my ($self, $user_id) = @_;

    my $row = $self->{dbh}->selectrow_hashref(
        q{
            select user_id, global_ability, uncertainty, updated_at
            from user_global_state
            where user_id = ?
            for update
        },
        undef,
        $user_id,
    );

    return $row if $row;

    return {
        user_id        => $user_id,
        global_ability => 0,
        uncertainty    => 1,
        updated_at     => undef,
    };
}

sub _upsert_user_skill_state {
    my ($self, $user_id, $skill_id, $next) = @_;

    $self->{dbh}->do(
        q{
            insert into user_skill_state (
                user_id,
                skill_id,
                ability,
                uncertainty,
                attempts,
                solves,
                last_practiced_at
            ) values (?, ?, ?, ?, ?, ?, ?)
            on conflict (user_id, skill_id) do update
            set ability = excluded.ability,
                uncertainty = excluded.uncertainty,
                attempts = excluded.attempts,
                solves = excluded.solves,
                last_practiced_at = excluded.last_practiced_at
        },
        undef,
        $user_id,
        $skill_id,
        $next->{ability},
        $next->{uncertainty},
        $next->{attempts},
        $next->{solves},
        $next->{last_practiced_at},
    );
}

sub _upsert_user_global_state {
    my ($self, $user_id, $global_ability, $attempted_at) = @_;

    $self->{dbh}->do(
        q{
            insert into user_global_state (user_id, global_ability, uncertainty, updated_at)
            values (?, ?, ?, ?)
            on conflict (user_id) do update
            set global_ability = excluded.global_ability,
                updated_at = excluded.updated_at
        },
        undef,
        $user_id,
        $global_ability,
        1,
        $attempted_at,
    );
}

sub _upsert_problem_rating_state {
    my ($self, %args) = @_;

    my $current         = $args{current};
    my $problem_id      = $args{problem_id};
    my $problem_delta   = $args{problem_delta} // 0;
    my $solved          = $args{solved} ? 1 : 0;
    my $first_try_solve = $args{first_try_solve} ? 1 : 0;

    $self->{dbh}->do(
        q{
            insert into problem_rating_state (
                problem_id,
                difficulty,
                uncertainty,
                attempts,
                solves,
                first_try_solves
            ) values (?, ?, ?, ?, ?, ?)
            on conflict (problem_id) do update
            set difficulty = excluded.difficulty,
                uncertainty = excluded.uncertainty,
                attempts = excluded.attempts,
                solves = excluded.solves,
                first_try_solves = excluded.first_try_solves
        },
        undef,
        $problem_id,
        $current->{difficulty} + $problem_delta,
        clamp(($current->{uncertainty} // 1) * $self->{uncertainty_decay}, $self->{min_uncertainty}, 1),
        ($current->{attempts} // 0) + 1,
        ($current->{solves} // 0) + $solved,
        ($current->{first_try_solves} // 0) + $first_try_solve,
    );
}

sub _upsert_user_problem_state {
    my ($self, %args) = @_;

    my $current      = $args{current};
    my $solved       = $args{solved} ? 1 : 0;
    my $attempted_at = $args{attempted_at};

    my $first_solved_at = $current->{first_solved_at};
    if ($solved && !$current->{solved} && !$first_solved_at) {
        $first_solved_at = $attempted_at;
    }

    $self->{dbh}->do(
        q{
            insert into user_problem_state (
                user_id,
                problem_id,
                attempts,
                solved,
                first_solved_at,
                last_attempt_at
            ) values (?, ?, ?, ?, ?, ?)
            on conflict (user_id, problem_id) do update
            set attempts = excluded.attempts,
                solved = excluded.solved,
                first_solved_at = excluded.first_solved_at,
                last_attempt_at = excluded.last_attempt_at
        },
        undef,
        $args{user_id},
        $args{problem_id},
        ($current->{attempts} // 0) + 1,
        ($current->{solved} || $solved) ? 1 : 0,
        $first_solved_at,
        $attempted_at,
    );
}

1;
