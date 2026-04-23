package web;
use strict;
use warnings;
use utf8;

sub parse_params {
    my ($source) = @_;
    my %params;

    return \%params unless defined $source && length $source;

    for my $pair (split /&/, $source) {
        next unless length $pair;
        my ($key, $value) = split /=/, $pair, 2;
        $key = url_decode($key // '');
        $value = url_decode($value // '');
        $params{$key} = $value;
    }

    return \%params;
}

sub read_post_params {
    my $length = $ENV{CONTENT_LENGTH} || 0;
    my $body = '';

    read(STDIN, $body, $length) if $length > 0;

    return parse_params($body);
}

sub parse_cookies {
    my ($raw) = @_;
    my %cookies;

    return \%cookies unless defined $raw && length $raw;

    for my $pair (split /\s*;\s*/, $raw) {
        next unless length $pair;
        my ($key, $value) = split /=/, $pair, 2;
        next unless defined $key && length $key;
        $cookies{$key} = defined $value ? $value : '';
    }

    return \%cookies;
}

sub build_headers {
    my (%args) = @_;

    my @lines;

    if (defined $args{location} && length $args{location}) {
        push @lines, 'Status: 302 Found';
        push @lines, 'Location: ' . $args{location};
    }

    push @lines, 'Content-Type: text/html; charset=UTF-8';

    if (defined $args{cookie} && length $args{cookie}) {
        push @lines, 'Set-Cookie: ' . $args{cookie};
    }

    return join("\n", @lines) . "\n\n";
}

sub make_cookie {
    my (%args) = @_;

    my $name    = $args{name}  || '';
    my $value   = defined $args{value} ? $args{value} : '';
    my $path    = $args{path} || '/';
    my $max_age = defined $args{max_age} ? $args{max_age} : undef;

    my @parts = (
        $name . '=' . $value,
        'Path=' . $path,
        'SameSite=Lax',
    );

    push @parts, 'Max-Age=' . $max_age if defined $max_age;

    return join('; ', @parts);
}

sub url_decode {
    my ($value) = @_;
    $value = '' unless defined $value;
    $value =~ tr/+/ /;
    $value =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
    return $value;
}

sub url_encode {
    my ($value) = @_;
    $value = '' unless defined $value;
    $value =~ s/([^A-Za-z0-9\-\._~])/sprintf('%%%02X', ord($1))/eg;
    return $value;
}

1;
