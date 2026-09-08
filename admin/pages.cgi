#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;

$ENV{MARK6_CONTENT_TYPE} = 'page';
my $result = do "$FindBin::Bin/articles.cgi";
die $@ if $@;
die "Cannot run articles.cgi: $!" unless defined $result;

