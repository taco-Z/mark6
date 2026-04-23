#!/usr/bin/perl
use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/lib";

use boot;
use router;
use web;

binmode STDOUT, ':encoding(UTF-8)';

my $ctx = boot::init('admin');
my $res = router::dispatch_admin($ctx);

print web::header_html(
    cookie => ($res->{cookie} || '')
);
print $res->{body};

#TEST
