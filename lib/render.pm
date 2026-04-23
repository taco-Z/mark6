package render;
use strict;
use warnings;
use utf8;

sub render_template {
    my ($template, $vars) = @_;
    $vars ||= {};

    my $output = defined $template ? $template : '';

    $output =~ s/\{\{([A-Za-z0-9_]+)\}\}/defined $vars->{$1} ? $vars->{$1} : ''/ge;

    return $output;
}

1;
