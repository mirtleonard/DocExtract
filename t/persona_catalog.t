use strict;
use warnings;

use Test::More;

use lib 'lib';

use DocExtract::AlgoRecommender::PersonaCatalog;

my $personas = DocExtract::AlgoRecommender::PersonaCatalog::all_personas();

is(scalar @{$personas}, 10, 'persona catalog exposes 10 synthetic learners');

my %seen_ids;
my %seen_slugs;

for my $persona (@{$personas}) {
    ok(!$seen_ids{ $persona->{user_id} }++, "user_id $persona->{user_id} is unique");
    ok(!$seen_slugs{ $persona->{slug} }++, "slug $persona->{slug} is unique");
    ok(length($persona->{name}) > 0, "persona $persona->{slug} has a display name");
    ok(@{ $persona->{submissions} || [] } >= 1, "persona $persona->{slug} has at least one scripted submission");

    for my $skill (@{ $persona->{initial_skills} || [] }) {
        like($skill->{skill_code}, qr/^[a-z_]+$/, "skill code $skill->{skill_code} is normalized");
        ok(defined $skill->{ability}, "skill $skill->{skill_code} defines ability");
    }

    for my $submission (@{ $persona->{submissions} || [] }) {
        ok($submission->{problem_id} =~ /^\d+$/, "submission for $persona->{slug} references a numeric problem id");
        like($submission->{created_at}, qr/^2026-05-01T\d{2}:\d{2}:\d{2}Z$/, "submission for $persona->{slug} has stable ISO timestamp");
    }
}

done_testing;
