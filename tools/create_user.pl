#!/usr/bin/env perl

use strict;
use warnings;
use Cwd qw(getcwd);
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

use Mark6::Auth;

my ($root, $name, $password, $rank, $help);

GetOptions(
    'root=s'     => \$root,
    'name=s'     => \$name,
    'password=s' => \$password,
    'rank=s'     => \$rank,
    'help'       => \$help,
) or usage(1);

usage(0) if $help;
usage(1) unless $name && $password;

$root ||= getcwd();
$rank ||= 'master';

my $auth = Mark6::Auth->new(root => $root);
my $user = $auth->create_user(
    name     => $name,
    password => $password,
    rank     => $rank,
);

print "Created user: $user->{name} ($user->{rank})\n";

sub usage {
    my ($exit) = @_;
    print <<"USAGE";
Usage:
  perl tools/create_user.pl --name admin --password secret [--rank master]

Options:
  --root      MARK6 project root. Defaults to current directory.
  --name      Login user name.
  --password  Login password.
  --rank      master, staff, or writer. Defaults to master.
USAGE
    exit $exit;
}

