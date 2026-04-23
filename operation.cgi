#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use CGI::Carp qw(fatalsToBrowser);

use FindBin;
use lib "$FindBin::Bin/lib";

use boot ();
use router ();
use web ();

binmode STDOUT, ':encoding(UTF-8)';

my $ctx = boot::init();
my $res = router::dispatch($ctx);

print web::build_headers(
    cookie   => $res->{cookie},
    location => $res->{location},
);

print $res->{body} // '';

