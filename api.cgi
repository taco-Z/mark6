#!/usr/bin/perl
use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/lib";

use boot;
use article;
use JSON::PP;
use web;

binmode STDOUT, ':encoding(UTF-8)';

my $ctx    = boot::init('api');
my $action = $ctx->{params}->{action} || 'article_list';

my $out;

if ($action eq 'article_get') {
    my $id = $ctx->{params}->{id} || '';
    $out = article::get_article($ctx, $id) || {};
} else {
    $out = article::list_articles($ctx);
}

print web::header_json();
print JSON::PP->new->utf8->canonical->encode($out);
