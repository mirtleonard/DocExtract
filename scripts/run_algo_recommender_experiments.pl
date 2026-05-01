#!/usr/bin/env perl

use strict;
use warnings;

use DBI;
use FindBin qw($Bin);
use lib "$Bin/../lib";

use DocExtract::AlgoRecommender::ExperimentRunner;

my $dsn = $ENV{DOCEXTRACT_DSN} || 'dbi:Pg:dbname=doc_extract';
my $db_user = $ENV{DOCEXTRACT_DB_USER};
my $db_password = $ENV{DOCEXTRACT_DB_PASSWORD};
my $export_path = $ENV{DOCEXTRACT_EXPERIMENT_EXPORT}
    || "$Bin/../docs/algo_recommender_experiment_report.json";

my $dbh = DBI->connect(
    $dsn,
    $db_user,
    $db_password,
    {
        RaiseError => 1,
        AutoCommit => 1,
        PrintError => 0,
        pg_enable_utf8 => 1,
    },
);

my $runner = DocExtract::AlgoRecommender::ExperimentRunner->new(
    dbh         => $dbh,
    top_n       => 5,
    export_path => $export_path,
);

my $result = $runner->run(
    run_label => 'postgres-synthetic-recommendation-demo',
);

print $runner->format_report($result), "\n";
print "JSON report: $export_path\n";
