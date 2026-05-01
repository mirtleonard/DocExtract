#!/usr/bin/env perl

use strict;
use warnings;

use Carp qw(croak);

my ($input_path, $output_path) = @ARGV;
croak "usage: $0 INPUT.txt OUTPUT.pdf" if !$input_path || !$output_path;

open my $in, '<:encoding(UTF-8)', $input_path or die "cannot open $input_path: $!";
my @raw_lines = <$in>;
close $in;

chomp @raw_lines;

my @pages;
my @current_page;
my $y = 760;
my $left_margin = 52;
my $bottom_margin = 44;

sub escape_pdf_text {
    my ($text) = @_;
    $text =~ s/\\/\\\\/g;
    $text =~ s/\(/\\(/g;
    $text =~ s/\)/\\)/g;
    return $text;
}

sub push_line {
    my ($page_ref, $font, $font_size, $leading, $x, $y_pos, $text) = @_;
    push @{$page_ref}, sprintf("BT /%s %.2f Tf %.2f TL 1 0 0 1 %.2f %.2f Tm (%s) Tj ET",
        $font,
        $font_size,
        $leading,
        $x,
        $y_pos,
        escape_pdf_text($text),
    );
}

sub wrap_text {
    my ($text, $width) = @_;
    $text =~ s/\s+/ /g;
    $text =~ s/^\s+|\s+$//g;
    return ('') if $text eq '';

    my @words = split / /, $text;
    my @lines;
    my $line = shift @words;

    for my $word (@words) {
        if (length($line) + 1 + length($word) <= $width) {
            $line .= ' ' . $word;
            next;
        }
        push @lines, $line;
        $line = $word;
    }

    push @lines, $line if defined $line && $line ne '';
    return @lines;
}

sub flush_page_if_needed {
    my ($pages_ref, $page_ref, $y_ref, $needed_height) = @_;
    if ($$y_ref - $needed_height < $bottom_margin) {
        push @{$pages_ref}, [ @{$page_ref} ] if @{$page_ref};
        @{$page_ref} = ();
        $$y_ref = 760;
    }
}

for my $raw (@raw_lines) {
    my $line = $raw;
    $line =~ s/\r$//;

    if ($line =~ /^# (.+)$/) {
        flush_page_if_needed(\@pages, \@current_page, \$y, 30);
        push_line(\@current_page, 'F2', 18, 22, $left_margin, $y, $1);
        $y -= 28;
        next;
    }

    if ($line =~ /^## (.+)$/) {
        flush_page_if_needed(\@pages, \@current_page, \$y, 24);
        $y -= 4;
        push_line(\@current_page, 'F2', 13, 16, $left_margin, $y, $1);
        $y -= 20;
        next;
    }

    if ($line eq '') {
        $y -= 8;
        next;
    }

    my @wrapped = wrap_text($line, 96);
    for my $wrapped (@wrapped) {
        flush_page_if_needed(\@pages, \@current_page, \$y, 14);
        push_line(\@current_page, 'F1', 10.5, 13, $left_margin, $y, $wrapped);
        $y -= 13;
    }
}

push @pages, [ @current_page ] if @current_page;

my @objects;

my $catalog_obj = 1;
my $pages_obj   = 2;
my $font1_obj   = 3;
my $font2_obj   = 4;

$objects[$catalog_obj] = "<< /Type /Catalog /Pages $pages_obj 0 R >>";
$objects[$font1_obj] = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>";
$objects[$font2_obj] = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>";

my @page_object_ids;
my @content_object_ids;
my $next_id = 5;

for my $page (@pages) {
    my $page_obj = $next_id++;
    my $content_obj = $next_id++;
    push @page_object_ids, $page_obj;
    push @content_object_ids, $content_obj;

    my $stream = join("\n", @{$page}) . "\n";
    my $length = length($stream);
    $objects[$content_obj] = "<< /Length $length >>\nstream\n$stream" . "endstream";
    $objects[$page_obj] = "<< /Type /Page /Parent $pages_obj 0 R /MediaBox [0 0 612 792] "
        . "/Resources << /Font << /F1 $font1_obj 0 R /F2 $font2_obj 0 R >> >> "
        . "/Contents $content_obj 0 R >>";
}

my $kids = join ' ', map { "$_ 0 R" } @page_object_ids;
$objects[$pages_obj] = "<< /Type /Pages /Count " . scalar(@page_object_ids) . " /Kids [ $kids ] >>";

open my $out, '>:raw', $output_path or die "cannot write $output_path: $!";
print {$out} "%PDF-1.4\n";

my @offsets;
$offsets[0] = 0;

for my $obj_id (1 .. $#objects) {
    $offsets[$obj_id] = tell($out);
    my $content = $objects[$obj_id];
    print {$out} "$obj_id 0 obj\n$content\nendobj\n";
}

my $xref_start = tell($out);
print {$out} "xref\n";
print {$out} "0 " . ($#objects + 1) . "\n";
print {$out} "0000000000 65535 f \n";

for my $obj_id (1 .. $#objects) {
    printf {$out} "%010d 00000 n \n", $offsets[$obj_id];
}

print {$out} "trailer\n";
print {$out} "<< /Size " . ($#objects + 1) . " /Root $catalog_obj 0 R >>\n";
print {$out} "startxref\n";
print {$out} "$xref_start\n";
print {$out} "%%EOF\n";

close $out;

