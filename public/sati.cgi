#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
BEGIN { unshift @INC, "$FindBin::Bin/../lib"; }
use Mark6::DataStore;
use Mark6::Root;
use Mark6::Extensions;

my $root = $ENV{MARK6_ROOT} || Mark6::Root::default_root(findbin => $FindBin::Bin, script => $0, marker => 'dat/users.json');
my $store = Mark6::DataStore->new(root => $root);
Mark6::Extensions::dispatch('memory', root => $root, config => $store->read_json('dat', 'config.json') || {});
