#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use Getopt::Long qw(GetOptions);

BEGIN {
    my @lib_candidates = (
        './lib',
        "$FindBin::Bin/../lib",
        '../lib',
    );

    for my $lib (@lib_candidates) {
        if (-d $lib) {
            unshift @INC, $lib;
            last;
        }
    }
}

use Mark6::Mark5Migration;

my ($from, $to, $help);

GetOptions(
    'from=s' => \$from,
    'to=s'   => \$to,
    'help'   => \$help,
) or usage(1);

usage(0) if $help;
usage(1) unless $from && $to;

my $migration = Mark6::Mark5Migration->new(
    from => $from,
    to   => $to,
);

my $report = $migration->run;

print "MARK5 to MARK6 migration finished.\n";
print "Written:\n";
print "  $_\n" for @{$report->{written}};

if (@{$report->{copied}}) {
    print "Copied:\n";
    print "  $_\n" for @{$report->{copied}};
}

if (@{$report->{skipped}}) {
    print "Skipped:\n";
    print "  $_\n" for @{$report->{skipped}};
}

if (@{$report->{warnings}}) {
    print "Warnings:\n";
    print "  $_\n" for @{$report->{warnings}};
}

sub usage {
    my ($exit) = @_;
    print <<"USAGE";
Usage:
  perl tools/migrate_mark5.pl --from /path/to/MARK5 --to /path/to/mark6

Example:
  perl tools/migrate_mark5.pl --from "D:\\projects\\mark5\\MARK5 1.0" --to "D:\\projects\\mark6"
USAGE
    exit $exit;
}
