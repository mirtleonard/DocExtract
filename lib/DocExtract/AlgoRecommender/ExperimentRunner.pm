package DocExtract::AlgoRecommender::ExperimentRunner;

use strict;
use warnings;

use Carp qw(croak);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use JSON::PP qw(encode_json);

use DocExtract::AlgoRecommender::PersonaCatalog;
use DocExtract::AlgoRecommender::RatingService;
use DocExtract::AlgoRecommender::RecommendationService;

sub new {
    my ($class, %args) = @_;

    my $dbh = $args{dbh} or croak 'dbh is required';
    my $personas = $args{personas} || DocExtract::AlgoRecommender::PersonaCatalog::all_personas();
    my $rating_service = $args{rating_service} || DocExtract::AlgoRecommender::RatingService->new(
        dbh => $dbh,
    );
    my $recommendation_service = $args{recommendation_service} || DocExtract::AlgoRecommender::RecommendationService->new(
        dbh                          => $dbh,
        rating_service               => $rating_service,
        recent_attempt_cooldown_days => defined $args{recent_attempt_cooldown_days}
            ? $args{recent_attempt_cooldown_days}
            : 0,
    );

    my $self = bless {
        dbh                    => $dbh,
        personas               => $personas,
        rating_service         => $rating_service,
        recommendation_service => $recommendation_service,
        top_n                  => $args{top_n} // 5,
        export_path            => $args{export_path},
    }, $class;

    return $self;
}

sub run {
    my ($self, %args) = @_;

    my $personas = $args{personas} || $self->{personas};
    my $export_path = $args{export_path} || $self->{export_path};
    my $run_label = $args{run_label} || 'synthetic-algo-recommender-experiment';

    my $skill_map = $self->_load_skill_map();
    my $problem_map = $self->_load_problem_map();

    $self->_validate_personas($personas, $skill_map, $problem_map);
    $self->_clear_synthetic_users($personas);

    my @results;
    for my $persona (@{$personas}) {
        $self->_seed_persona($persona, $skill_map);

        my $before = {
            global_ability => $self->_load_user_global_ability($persona->{user_id}),
            skills         => $self->_load_user_skills_snapshot($persona->{user_id}, $skill_map),
            recommendations => $self->{recommendation_service}->recommend_for_user(
                user_id => $persona->{user_id},
                limit   => $self->{top_n},
            ),
        };

        my @events;
        for my $submission (@{ $persona->{submissions} || [] }) {
            $self->_insert_submission($persona->{user_id}, $submission);

            my $rating_result = $self->{rating_service}->record_submission(
                user_id    => $persona->{user_id},
                problem_id => $submission->{problem_id},
                submission => $submission,
            );

            push @events, {
                problem_id   => $submission->{problem_id},
                problem_title => $problem_map->{ $submission->{problem_id} },
                verdict      => $submission->{verdict},
                created_at   => $submission->{created_at},
                tests_passed => $submission->{tests_passed},
                tests_total  => $submission->{tests_total},
                observed     => $rating_result->{observed},
                predicted    => $rating_result->{predicted},
                solved       => $rating_result->{solved},
            };
        }

        my $after = {
            global_ability => $self->_load_user_global_ability($persona->{user_id}),
            skills         => $self->_load_user_skills_snapshot($persona->{user_id}, $skill_map),
            recommendations => $self->{recommendation_service}->recommend_for_user(
                user_id => $persona->{user_id},
                limit   => $self->{top_n},
            ),
        };

        push @results, {
            user_id => $persona->{user_id},
            slug    => $persona->{slug},
            name    => $persona->{name},
            description => $persona->{description},
            before  => $before,
            submissions => \@events,
            after   => $after,
        };
    }

    my $result = {
        run_label => $run_label,
        generated_at => _utc_now_iso(),
        persona_count => scalar @results,
        top_n => $self->{top_n},
        personas => \@results,
    };

    $self->_write_json_report($export_path, $result) if defined $export_path;

    return $result;
}

sub format_report {
    my ($self, $result) = @_;

    my @lines;
    push @lines, sprintf('Experiment: %s', $result->{run_label});
    push @lines, sprintf('Generated at: %s', $result->{generated_at});
    push @lines, q{};

    for my $persona (@{ $result->{personas} || [] }) {
        push @lines, sprintf('[%s] %s (%s)', $persona->{user_id}, $persona->{name}, $persona->{slug});
        push @lines, $persona->{description};
        push @lines, sprintf('  Global ability: %.3f -> %.3f', $persona->{before}{global_ability}, $persona->{after}{global_ability});
        push @lines, '  Initial recommendations:';
        push @lines, map {
            sprintf(
                '    - %s [p=%.3f score=%.3f]',
                $_->{title} || $_->{problem_id},
                $_->{solve_probability},
                $_->{recommendation_score},
            )
        } @{ $persona->{before}{recommendations} || [] };

        push @lines, '  Submission replay:';
        push @lines, map {
            sprintf(
                '    - %s: %s (pred=%.3f, obs=%.3f, solved=%s)',
                $_->{problem_title} || $_->{problem_id},
                $_->{verdict},
                $_->{predicted},
                $_->{observed},
                $_->{solved} ? 'yes' : 'no',
            )
        } @{ $persona->{submissions} || [] };

        push @lines, '  Final recommendations:';
        push @lines, map {
            sprintf(
                '    - %s [p=%.3f score=%.3f]',
                $_->{title} || $_->{problem_id},
                $_->{solve_probability},
                $_->{recommendation_score},
            )
        } @{ $persona->{after}{recommendations} || [] };

        push @lines, q{};
    }

    return join "\n", @lines;
}

sub _load_skill_map {
    my ($self) = @_;

    my $rows = $self->{dbh}->selectall_arrayref(
        q{
            select id, code, name
            from skills
            order by id asc
        },
        { Slice => {} },
    );

    my (%by_code, %by_id);
    for my $row (@{$rows}) {
        $by_code{ $row->{code} } = {
            id   => $row->{id},
            code => $row->{code},
            name => $row->{name},
        };
        $by_id{ $row->{id} } = $by_code{ $row->{code} };
    }

    return {
        by_code => \%by_code,
        by_id   => \%by_id,
    };
}

sub _load_problem_map {
    my ($self) = @_;

    my $rows = $self->{dbh}->selectall_arrayref(
        q{
            select id, title
            from problems
            order by id asc
        },
        { Slice => {} },
    );

    my %map = map { $_->{id} => $_->{title} } @{$rows};
    return \%map;
}

sub _validate_personas {
    my ($self, $personas, $skill_map, $problem_map) = @_;

    my %seen_ids;
    for my $persona (@{$personas}) {
        croak "duplicate persona user_id $persona->{user_id}" if $seen_ids{ $persona->{user_id} }++;
        for my $skill (@{ $persona->{initial_skills} || [] }) {
            croak "unknown skill code $skill->{skill_code} for persona $persona->{slug}"
                if !exists $skill_map->{by_code}{ $skill->{skill_code} };
        }
        for my $problem_id (@{ $persona->{pre_solved_problem_ids} || [] }) {
            croak "unknown pre-solved problem $problem_id for persona $persona->{slug}"
                if !exists $problem_map->{$problem_id};
        }
        for my $submission (@{ $persona->{submissions} || [] }) {
            croak "unknown submitted problem $submission->{problem_id} for persona $persona->{slug}"
                if !exists $problem_map->{ $submission->{problem_id} };
        }
    }
}

sub _clear_synthetic_users {
    my ($self, $personas) = @_;

    my @user_ids = map { $_->{user_id} } @{$personas};
    my $min_user_id = $user_ids[0];
    my $max_user_id = $user_ids[0];
    for my $user_id (@user_ids) {
        $min_user_id = $user_id if $user_id < $min_user_id;
        $max_user_id = $user_id if $user_id > $max_user_id;
    }

    for my $table (qw(recommendation_cache submissions user_problem_state user_skill_state user_global_state)) {
        $self->{dbh}->do(
            "delete from $table where user_id between ? and ?",
            undef,
            $min_user_id,
            $max_user_id,
        );
    }
}

sub _seed_persona {
    my ($self, $persona, $skill_map) = @_;

    $self->{dbh}->do(
        q{
            insert into user_global_state (user_id, global_ability, uncertainty, updated_at)
            values (?, ?, ?, ?)
            on conflict (user_id) do update
            set global_ability = excluded.global_ability,
                uncertainty = excluded.uncertainty,
                updated_at = excluded.updated_at
        },
        undef,
        $persona->{user_id},
        $persona->{initial_global_ability},
        1,
        '2026-05-01T08:55:00Z',
    );

    for my $skill (@{ $persona->{initial_skills} || [] }) {
        my $skill_id = $skill_map->{by_code}{ $skill->{skill_code} }{id};
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
            $persona->{user_id},
            $skill_id,
            $skill->{ability},
            defined $skill->{uncertainty} ? $skill->{uncertainty} : 1,
            $skill->{attempts} // 0,
            $skill->{solves} // 0,
            '2026-05-01T08:55:00Z',
        );
    }

    for my $problem_id (@{ $persona->{pre_solved_problem_ids} || [] }) {
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
            $persona->{user_id},
            $problem_id,
            1,
            1,
            '2026-05-01T08:50:00Z',
            '2026-05-01T08:50:00Z',
        );
    }
}

sub _insert_submission {
    my ($self, $user_id, $submission) = @_;

    $self->{dbh}->do(
        q{
            insert into submissions (
                user_id,
                problem_id,
                verdict,
                score,
                runtime_ms,
                memory_kb,
                tests_passed,
                tests_total,
                hint_used,
                editorial_used,
                created_at
            ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        },
        undef,
        $user_id,
        $submission->{problem_id},
        $submission->{verdict},
        $submission->{score},
        $submission->{runtime_ms},
        $submission->{memory_kb},
        $submission->{tests_passed},
        $submission->{tests_total},
        $submission->{hint_used} ? 1 : 0,
        $submission->{editorial_used} ? 1 : 0,
        $submission->{created_at},
    );
}

sub _load_user_global_ability {
    my ($self, $user_id) = @_;

    my ($global_ability) = $self->{dbh}->selectrow_array(
        q{
            select global_ability
            from user_global_state
            where user_id = ?
        },
        undef,
        $user_id,
    );

    return $global_ability // 0;
}

sub _load_user_skills_snapshot {
    my ($self, $user_id, $skill_map) = @_;

    my $rows = $self->{dbh}->selectall_arrayref(
        q{
            select skill_id, ability, uncertainty, attempts, solves, last_practiced_at
            from user_skill_state
            where user_id = ?
            order by attempts desc, skill_id asc
        },
        { Slice => {} },
        $user_id,
    );

    my @skills;
    for my $row (@{$rows}) {
        my $skill = $skill_map->{by_id}{ $row->{skill_id} } || {};
        push @skills, {
            skill_id => $row->{skill_id},
            skill_code => $skill->{code},
            skill_name => $skill->{name},
            ability => $row->{ability},
            uncertainty => $row->{uncertainty},
            attempts => $row->{attempts},
            solves => $row->{solves},
            last_practiced_at => $row->{last_practiced_at},
        };
    }

    return \@skills;
}

sub _write_json_report {
    my ($self, $path, $result) = @_;

    my $dir = dirname($path);
    make_path($dir) if $dir && !-d $dir;

    open my $fh, '>:encoding(UTF-8)', $path or die "cannot write $path: $!";
    print {$fh} JSON::PP->new->canonical->pretty->encode($result);
    close $fh;
}

sub _utc_now_iso {
    my @gmt = gmtime();

    return sprintf(
        '%04d-%02d-%02dT%02d:%02d:%02dZ',
        $gmt[5] + 1900,
        $gmt[4] + 1,
        $gmt[3],
        $gmt[2],
        $gmt[1],
        $gmt[0],
    );
}

1;
