package Mark6::Root;

use strict;
use warnings;
use Cwd qw(abs_path getcwd);
use File::Basename qw(dirname);

sub default_root {
    my (%args) = @_;
    my $findbin = $args{findbin} || '';
    my $script = abs_path($args{script} || $0);
    my $marker = $args{marker} || '';

    my @candidates = (
        defined($script) && $script ne '' ? dirname(dirname($script)) : (),
        $findbin ne '' ? "$findbin/.." : (),
        dirname(getcwd()),
        getcwd(),
    );

    for my $candidate (@candidates) {
        next unless defined $candidate && $candidate ne '';
        next unless -d $candidate;
        return $candidate if $marker eq '' || -e "$candidate/$marker";
    }

    for my $candidate (@candidates) {
        next unless defined $candidate && $candidate ne '';
        return $candidate if -d $candidate;
    }

    return $findbin ne '' ? "$findbin/.." : '.';
}

1;
