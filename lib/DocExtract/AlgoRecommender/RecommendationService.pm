package DocExtract::AlgoRecommender::RecommendationService;

use strict;
use warnings;

use Carp qw(croak);

use DocExtract::AlgoRecommender::Util qw(ability_to_mastery clamp);
use DocExtract::AlgoRecommender::RatingService;

sub new {
    my ($class, %args) = @_;

    my $self = bless {
        dbh                => $args{dbh},
        target_probability => $args{target_probability} // 0.72,
        candidate_limit    => $args{candidate_limit} // 200,
        rating_service     => $args{rating_service} || DocExtract::AlgoRecommender::RatingService->new(),
    }, $class;

    return $self;
}

sub score_candidate {
    my ($self, %args) = @_;

    my $problem         = $args{problem} or croak 'problem is required';
    my $skill_weights   = $problem->{skills} || [];
    my $user_skills     = $args{user_skills} || {};
    my $global_bias     = $args{global_bias} // 0;
    my $solve_prob      = $self->{rating_service}->predict_probability(
        abilities     => $user_skills,
        skill_weights => $skill_weights,
        difficulty    => $problem->{difficulty},
        global_bias   => $global_bias,
    );

    my $target = $self->{target_probability};
    my $challenge_fit = 1 - clamp(abs($solve_prob - $target) / $target, 0, 1);

    my ($weak_skill_coverage, $uncertainty_reduction) = (0, 0);
    my $weight_sum = 0;
    for my $skill (@{$skill_weights}) {
        my $weight      = $skill->{weight} // 0;
        my $skill_state = $user_skills->{$skill->{skill_id}} || {};
        my $mastery     = ability_to_mastery($skill_state->{ability} // 0);
        my $uncertainty = defined $skill_state->{uncertainty} ? $skill_state->{uncertainty} : 1;

        $weak_skill_coverage += $weight * (1 - $mastery);
        $uncertainty_reduction += $weight * $uncertainty;
        $weight_sum += $weight;
    }

    if ($weight_sum > 0) {
        $weak_skill_coverage /= $weight_sum;
        $uncertainty_reduction /= $weight_sum;
    }

    my $attempts = $problem->{historical_attempts} // 0;
    my $novelty = 1 - clamp($attempts / 50, 0, 0.8);

    my $frustration_risk = 0;
    $frustration_risk = clamp((0.45 - $solve_prob) / 0.45, 0, 1) if $solve_prob < 0.45;

    my $score =
          0.45 * $challenge_fit
        + 0.25 * $weak_skill_coverage
        + 0.20 * $uncertainty_reduction
        + 0.10 * $novelty
        - 0.20 * $frustration_risk;

    return {
        problem_id             => $problem->{problem_id},
        solve_probability      => $solve_prob,
        challenge_fit          => $challenge_fit,
        weak_skill_coverage    => $weak_skill_coverage,
        uncertainty_reduction  => $uncertainty_reduction,
        novelty                => $novelty,
        frustration_risk       => $frustration_risk,
        recommendation_score   => $score,
    };
}

sub rank_candidates {
    my ($self, %args) = @_;

    my $problems    = $args{problems} || [];
    my $user_skills = $args{user_skills} || {};
    my $global_bias = $args{global_bias} // 0;

    my @scored = map {
        my $score = $self->score_candidate(
            problem     => $_,
            user_skills => $user_skills,
            global_bias => $global_bias,
        );
        +{
            %{$score},
            title => $_->{title},
        };
    } @{$problems};

    @scored = sort {
        $b->{recommendation_score} <=> $a->{recommendation_score}
            ||
        $b->{solve_probability} <=> $a->{solve_probability}
    } @scored;

    return \@scored;
}

sub recommend_for_user {
    my ($self, %args) = @_;

    my $dbh = $self->{dbh} or croak 'dbh is required for recommend_for_user';
    my $user_id = $args{user_id} or croak 'user_id is required';
    my $limit = $args{limit} // 20;

    my $user_skills = $self->_load_user_skill_state($dbh, $user_id);
    my $global_bias = $self->_load_user_global_ability($dbh, $user_id);
    my $problems = $self->_load_candidate_problems($dbh, $user_id);

    my $ranked = $self->rank_candidates(
        problems    => $problems,
        user_skills => $user_skills,
        global_bias => $global_bias,
    );

    if (@{$ranked} > $limit) {
        splice @{$ranked}, $limit;
    }

    return $ranked;
}

sub _load_user_skill_state {
    my ($self, $dbh, $user_id) = @_;

    my $rows = $dbh->selectall_arrayref(
        q{
            select skill_id, ability, uncertainty, attempts, solves, last_practiced_at
            from user_skill_state
            where user_id = ?
        },
        { Slice => {} },
        $user_id,
    );

    my %user_skills = map { $_->{skill_id} => $_ } @{$rows};
    return \%user_skills;
}

sub _load_user_global_ability {
    my ($self, $dbh, $user_id) = @_;

    my ($global_ability) = $dbh->selectrow_array(
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

sub _load_candidate_problems {
    my ($self, $dbh, $user_id) = @_;

    my $rows = $dbh->selectall_arrayref(
        q{
            select
                p.id as problem_id,
                p.title,
                prs.difficulty,
                prs.attempts as historical_attempts
            from problems p
            join problem_rating_state prs on prs.problem_id = p.id
            left join user_problem_state ups
              on ups.problem_id = p.id
             and ups.user_id = ?
            where coalesce(ups.solved, false) = false
              and (
                    ups.last_attempt_at is null
                 or ups.last_attempt_at < now() - interval '3 days'
              )
            order by prs.attempts desc, p.id asc
            limit ?
        },
        { Slice => {} },
        $user_id,
        $self->{candidate_limit},
    );

    return [] if !@{$rows};

    my @problem_ids = map { $_->{problem_id} } @{$rows};
    my $placeholders = join q{, }, ('?') x @problem_ids;
    my $skill_rows = $dbh->selectall_arrayref(
        qq{
            select problem_id, skill_id, weight
            from problem_skills
            where problem_id in ($placeholders)
            order by problem_id asc, weight desc, skill_id asc
        },
        { Slice => {} },
        @problem_ids,
    );

    my %skills_by_problem;
    for my $row (@{$skill_rows}) {
        push @{$skills_by_problem{$row->{problem_id}}}, {
            skill_id => $row->{skill_id},
            weight   => $row->{weight},
        };
    }

    for my $problem (@{$rows}) {
        $problem->{skills} = $skills_by_problem{$problem->{problem_id}} || [];
    }

    return $rows;
}

1;
