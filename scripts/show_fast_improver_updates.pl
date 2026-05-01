#!/usr/bin/env perl

# show_fast_improver_updates.pl
# Prints all DB-recorded updates for the Fast Improver user (user_id 9009).
#
# Usage:
#   DOCEXTRACT_DSN="dbi:Pg:dbname=doc_extract" \
#   DOCEXTRACT_DB_USER=myuser \
#   DOCEXTRACT_DB_PASSWORD=mypass \
#   perl scripts/show_fast_improver_updates.pl

use strict;
use warnings;

use DBI;
use FindBin qw($Bin);
use lib "$Bin/../lib";

# ---------------------------------------------------------------------------
# Connection
# ---------------------------------------------------------------------------
my $dsn      = $ENV{DOCEXTRACT_DSN}         || 'dbi:Pg:dbname=doc_extract';
my $db_user  = $ENV{DOCEXTRACT_DB_USER};
my $db_pass  = $ENV{DOCEXTRACT_DB_PASSWORD};

my $USER_ID  = 9009;
my $USER_NAME = 'Fast Improver';

my $dbh = DBI->connect(
    $dsn, $db_user, $db_pass,
    { RaiseError => 1, AutoCommit => 1, PrintError => 0, pg_enable_utf8 => 1 },
);

# ---------------------------------------------------------------------------
# Helper: print a section header and a result set as a plain table
# ---------------------------------------------------------------------------
sub print_section {
    my ($title, $rows, $cols) = @_;

    print "\n";
    print "=" x 60, "\n";
    print "  $title\n";
    print "=" x 60, "\n";

    unless (@$rows) {
        print "  (no rows)\n";
        return;
    }

    # Column widths
    my %w;
    for my $col (@$cols) { $w{$col} = length($col) }
    for my $row (@$rows) {
        for my $col (@$cols) {
            my $len = length($row->{$col} // '');
            $w{$col} = $len if $len > $w{$col};
        }
    }

    my $fmt = join('  ', map { "%-$w{$_}s" } @$cols) . "\n";

    printf $fmt, @$cols;
    print "-" x (60), "\n";
    for my $row (@$rows) {
        printf $fmt, map { $row->{$_} // '' } @$cols;
    }
}

# ---------------------------------------------------------------------------
# 1. Submissions — the raw history of every attempt
# ---------------------------------------------------------------------------
my $submissions = $dbh->selectall_arrayref(<<'SQL', { Slice => {} }, $USER_ID);
    SELECT
        s.id,
        p.title          AS problem,
        s.verdict,
        s.score,
        s.tests_passed,
        s.tests_total,
        s.hint_used,
        s.editorial_used,
        s.created_at
    FROM submissions s
    JOIN problems   p ON p.id = s.problem_id
    WHERE s.user_id = ?
    ORDER BY s.created_at
SQL

print_section(
    "Submissions for $USER_NAME (user_id=$USER_ID)",
    $submissions,
    [qw(id problem verdict score tests_passed tests_total hint_used editorial_used created_at)],
);

# ---------------------------------------------------------------------------
# 2. Global state — current overall ability snapshot
# ---------------------------------------------------------------------------
my $global = $dbh->selectall_arrayref(<<'SQL', { Slice => {} }, $USER_ID);
    SELECT
        user_id,
        global_ability,
        uncertainty,
        updated_at
    FROM user_global_state
    WHERE user_id = ?
SQL

print_section(
    "Global State for $USER_NAME (user_id=$USER_ID)",
    $global,
    [qw(user_id global_ability uncertainty updated_at)],
);

# ---------------------------------------------------------------------------
# 3. Skill state — per-skill ability, attempts, solves
# ---------------------------------------------------------------------------
my $skills = $dbh->selectall_arrayref(<<'SQL', { Slice => {} }, $USER_ID);
    SELECT
        sk.code         AS skill,
        uss.ability,
        uss.uncertainty,
        uss.attempts,
        uss.solves,
        uss.last_practiced_at
    FROM user_skill_state uss
    JOIN skills sk ON sk.id = uss.skill_id
    WHERE uss.user_id = ?
    ORDER BY uss.ability DESC
SQL

print_section(
    "Skill State for $USER_NAME (user_id=$USER_ID)",
    $skills,
    [qw(skill ability uncertainty attempts solves last_practiced_at)],
);

# ---------------------------------------------------------------------------
# 4. Problem state — per-problem attempts and solve status
# ---------------------------------------------------------------------------
my $problems = $dbh->selectall_arrayref(<<'SQL', { Slice => {} }, $USER_ID);
    SELECT
        p.title          AS problem,
        ups.attempts,
        ups.solved,
        ups.first_solved_at,
        ups.last_attempt_at
    FROM user_problem_state ups
    JOIN problems p ON p.id = ups.problem_id
    WHERE ups.user_id = ?
    ORDER BY ups.last_attempt_at
SQL

print_section(
    "Problem State for $USER_NAME (user_id=$USER_ID)",
    $problems,
    [qw(problem attempts solved first_solved_at last_attempt_at)],
);

print "\n";
$dbh->disconnect;
