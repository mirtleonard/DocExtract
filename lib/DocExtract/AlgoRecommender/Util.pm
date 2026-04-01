package DocExtract::AlgoRecommender::Util;

use strict;
use warnings;

use Exporter 'import';

our @EXPORT_OK = qw(sigmoid clamp weighted_sum ability_to_mastery);

sub sigmoid {
    my ($value) = @_;

    return 1 if $value >= 35;
    return 0 if $value <= -35;

    return 1 / (1 + exp(-$value));
}

sub clamp {
    my ($value, $min, $max) = @_;

    return $min if $value < $min;
    return $max if $value > $max;

    return $value;
}

sub weighted_sum {
    my ($abilities, $skill_weights) = @_;

    my $sum = 0;
    for my $skill (@{$skill_weights}) {
        my $skill_id = $skill->{skill_id};
        my $weight   = $skill->{weight} // 0;
        my $ability  = $abilities->{$skill_id}{ability} // 0;
        $sum += $ability * $weight;
    }

    return $sum;
}

sub ability_to_mastery {
    my ($ability) = @_;

    return sigmoid($ability);
}

1;
