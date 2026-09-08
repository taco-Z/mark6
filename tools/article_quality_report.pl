#!/usr/bin/env perl

use strict;
use warnings;
use utf8;
use Encode qw(encode);
use File::Spec;
use FindBin;
use Getopt::Long qw(GetOptions);

BEGIN {
    unshift @INC, "$FindBin::Bin/../lib" if -d "$FindBin::Bin/../lib";
}

use Mark6::QualityReport;

my %args = (
    root    => File::Spec->rel2abs(File::Spec->catdir($FindBin::Bin, '..')),
    node    => '',
    profile => 'generic',
    output  => '',
    csv     => '',
);

GetOptions(
    'root=s'    => \$args{root},
    'node=s'    => \$args{node},
    'profile=s' => \$args{profile},
    'output=s'  => \$args{output},
    'csv=s'     => \$args{csv},
) or usage();

my $reporter = Mark6::QualityReport->new(
    root    => $args{root},
    node    => $args{node},
    profile => $args{profile},
);
my $report = $reporter->generate;
my $markdown = $args{output} || Mark6::QualityReport::default_markdown_path($args{root}, $args{profile});
my $csv = $args{csv} || Mark6::QualityReport::default_csv_path($args{root}, $args{profile});

Mark6::QualityReport::write_markdown($report, $markdown);
Mark6::QualityReport::write_csv($report, $csv);

my $needs_work = grep { $_->{status} ne 'OK' } @{$report->{rows}};
print encode('UTF-8', "Scanned $report->{counts}{parsed} article(s); $needs_work need review. Report: $markdown\n");

sub usage {
    die <<"USAGE";
Usage: perl tools/article_quality_report.pl [--root PATH] [--node NODE] [--profile generic|oita360] [--output PATH] [--csv PATH]
USAGE
}
