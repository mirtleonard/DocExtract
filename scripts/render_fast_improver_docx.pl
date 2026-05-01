#!/usr/bin/env perl

use strict;
use warnings;

use Archive::Zip qw(:ERROR_CODES :CONSTANTS);
use File::Basename qw(dirname);
use File::Path qw(make_path);

my ($output_path) = @ARGV;
$output_path ||= 'docs/fast_improver_experiment_summary.docx';

make_path(dirname($output_path)) if dirname($output_path) && !-d dirname($output_path);

sub xml_escape {
    my ($text) = @_;
    $text =~ s/&/&amp;/g;
    $text =~ s/</&lt;/g;
    $text =~ s/>/&gt;/g;
    $text =~ s/"/&quot;/g;
    $text =~ s/'/&apos;/g;
    return $text;
}

sub paragraph {
    my ($text, $style) = @_;
    my $style_xml = defined $style ? qq{<w:pPr><w:pStyle w:val="$style"/></w:pPr>} : q{};
    return qq{<w:p>$style_xml<w:r><w:t>} . xml_escape($text) . qq{</w:t></w:r></w:p>};
}

sub table {
    my ($headers, $rows) = @_;

    my $xml = q{<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/><w:tblBorders><w:top w:val="single" w:sz="4" w:space="0" w:color="D1D5DB"/><w:left w:val="single" w:sz="4" w:space="0" w:color="D1D5DB"/><w:bottom w:val="single" w:sz="4" w:space="0" w:color="D1D5DB"/><w:right w:val="single" w:sz="4" w:space="0" w:color="D1D5DB"/><w:insideH w:val="single" w:sz="4" w:space="0" w:color="D1D5DB"/><w:insideV w:val="single" w:sz="4" w:space="0" w:color="D1D5DB"/></w:tblBorders></w:tblPr>};

    $xml .= table_row($headers, 1);
    for my $row (@{$rows}) {
        $xml .= table_row($row, 0);
    }

    return $xml . q{</w:tbl>};
}

sub table_row {
    my ($cells, $is_header) = @_;

    my $xml = q{<w:tr>};
    for my $cell (@{$cells}) {
        my $bold_start = $is_header ? q{<w:b/>} : q{};
        my $fill = $is_header ? q{<w:tcPr><w:shd w:fill="F3F4F6"/></w:tcPr>} : q{};
        $xml .= q{<w:tc>} . $fill . q{<w:p><w:r><w:rPr>} . $bold_start . q{</w:rPr><w:t>}
            . xml_escape($cell)
            . q{</w:t></w:r></w:p></w:tc>};
    }
    return $xml . q{</w:tr>};
}

my @body = (
    paragraph('Fast Improver Experiment Summary', 'Title'),
    paragraph('Source report: docs/algo_recommender_experiment_report.json'),
    paragraph('This summary extracts one learner from the experiment report: Fast Improver, user 9009.'),
    paragraph('User Overview', 'Heading1'),
    paragraph('Fast Improver starts near beginner level, then improves quickly after solving hashing and sliding-window style problems. Their global ability moved from -0.3500 to -0.3041, so the system learned that they are stronger than their initial profile suggested.'),
    paragraph('Submission Replay', 'Heading1'),
    table(
        ['Problem', 'Result', 'Predicted', 'Observed', 'Effect'],
        [
            ['Two Sum', 'wrong answer', '0.517', '0.300', 'user underperformed, problem got slightly harder'],
            ['Two Sum', 'accepted', '0.510', '0.850', 'user improved, problem got easier'],
            ['Max Sum Subarray of Size K', 'accepted', '0.322', '1.000', 'strong overperformance'],
            ['Longest Substring Without Repeats', 'accepted', '0.275', '1.000', 'very strong overperformance'],
        ],
    ),
    paragraph('Skill Progress', 'Heading1'),
    table(
        ['Skill', 'Before', 'After'],
        [
            ['arrays', '0.0000', '0.0019'],
            ['hashing', '-0.1000', '-0.0690'],
            ['two_pointers', '-0.1800', '-0.1800'],
            ['sliding_window', 'not present', '0.0891'],
        ],
    ),
    paragraph('Problem Progress', 'Heading1'),
    table(
        ['Problem', 'Seed Difficulty', 'Current Difficulty', 'Meaning'],
        [
            ['Two Sum', '-0.5000', '-0.5061', 'slightly easier after the final accepted solve'],
            ['Max Sum Subarray of Size K', '0.4000', '0.3661', 'easier because the user solved it despite low predicted probability'],
            ['Longest Substring Without Repeats', '0.6600', '0.6047', 'easier overall after experiment users performed well on it'],
        ],
    ),
    paragraph('Important nuance: current_difficulty is the result after the whole experiment run, so for Longest Substring Without Repeats it includes other synthetic users too, not only user 9009.'),
    paragraph('Final Recommendations', 'Heading1'),
    table(
        ['Rank', 'Problem', 'Solve Probability', 'Score'],
        [
            ['1', 'Palindrome String', '0.689', '0.856'],
            ['2', 'Contains Duplicate', '0.629', '0.790'],
            ['3', 'Reverse an Array', '0.805', '0.789'],
            ['4', 'Find Maximum Element', '0.823', '0.780'],
            ['5', 'FizzBuzz', '0.879', '0.771'],
        ],
    ),
    paragraph('Interpretation', 'Heading1'),
    paragraph('For this user, the next best recommendation is Palindrome String: it is still approachable, but not too trivial, and it keeps them practicing foundational pattern recognition before moving deeper into harder sliding-window and hash-map problems.'),
);

my $document_xml = q{<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>}
  . join('', @body)
  . q{<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr></w:body>
</w:document>};

my $styles_xml = q{<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:style w:type="paragraph" w:styleId="Normal"><w:name w:val="Normal"/></w:style>
  <w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:rPr><w:b/><w:sz w:val="32"/></w:rPr></w:style>
  <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:rPr><w:b/><w:sz w:val="24"/></w:rPr></w:style>
</w:styles>};

my $content_types = q{<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>};

my $rels = q{<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>};

my $document_rels = q{<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>};

my $zip = Archive::Zip->new();
$zip->addString($content_types, '[Content_Types].xml');
$zip->addString($rels, '_rels/.rels');
$zip->addString($document_xml, 'word/document.xml');
$zip->addString($styles_xml, 'word/styles.xml');
$zip->addString($document_rels, 'word/_rels/document.xml.rels');

my $status = $zip->writeToFileNamed($output_path);
die "failed to write $output_path: $status" if $status != AZ_OK;

print "$output_path\n";
