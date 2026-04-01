#!/usr/bin/env perl

use strict;
use warnings;

use DBI;
use FindBin qw($Bin);
use lib "$Bin/../lib";

use DocExtract::AlgoRecommender::RatingService;
use DocExtract::AlgoRecommender::RecommendationService;

my $dsn = $ENV{DOCEXTRACT_DSN} || 'dbi:Pg:dbname=doc_extract';
my $dbh = DBI->connect(
    $dsn,
    $ENV{DOCEXTRACT_DB_USER},
    $ENV{DOCEXTRACT_DB_PASSWORD},
    {
        RaiseError => 1,
        AutoCommit => 1,
        PrintError => 0,
        pg_enable_utf8 => 1,
    },
);

my $rating = DocExtract::AlgoRecommender::RatingService->new(
    dbh       => $dbh,
    user_k    => 0.08,
    problem_k => 0.05,
);

my $recommendation = DocExtract::AlgoRecommender::RecommendationService->new(
    dbh            => $dbh,
    rating_service => $rating,
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

print "Predicted solve probability before update: $result->{predicted}\n";
print "Observed credit: $result->{observed}\n";

my $recommendations = $recommendation->recommend_for_user(
    user_id => 42,
    limit   => 5,
);

for my $row (@{$recommendations}) {
    printf(
        "%s score=%.4f solve_prob=%.4f\n",
        $row->{problem_id},
        $row->{recommendation_score},
        $row->{solve_probability},
    );
}
