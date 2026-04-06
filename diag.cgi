#!/usr/bin/perl
use strict;
use warnings;
use utf8;

print "Content-Type: text/plain; charset=UTF-8\n\n";
print "STEP 1\n";

use FindBin;
print "STEP 2\n";

use lib "$FindBin::Bin/lib";
print "STEP 3\n";

eval { require web;    web->import();    print "web ok\n";    1; } or print "web err: $@\n";
eval { require boot;   boot->import();   print "boot ok\n";   1; } or print "boot err: $@\n";
eval { require db;     db->import();     print "db ok\n";     1; } or print "db err: $@\n";
eval { require auth;   auth->import();   print "auth ok\n";   1; } or print "auth err: $@\n";
eval { require lang;   lang->import();   print "lang ok\n";   1; } or print "lang err: $@\n";
eval { require render; render->import(); print "render ok\n"; 1; } or print "render err: $@\n";
eval { require article;article->import();print "article ok\n";1; } or print "article err: $@\n";
eval { require router; router->import(); print "router ok\n"; 1; } or print "router err: $@\n";

print "DONE\n";
