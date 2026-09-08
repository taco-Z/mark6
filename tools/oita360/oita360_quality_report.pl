#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use File::Spec;

my $tool = File::Spec->catfile($FindBin::Bin, '..', 'article_quality_report.pl');
my @args = (
    $^X,
    $tool,
    '--profile', 'regional_media',
    '--node', 'oita360',
    @ARGV,
);

exec @args or die "Cannot exec $tool: $!";
