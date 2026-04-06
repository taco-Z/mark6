package web;
use strict;
use warnings;
use utf8;

sub parse_params {
    my %params;
    my $method = $ENV{REQUEST_METHOD} || 'GET';
    my $query  = '';

    if ($method eq 'POST') {
        my $len = $ENV{CONTENT_LENGTH} || 0;
        read(STDIN, $query, $len) if $len > 0;
        if (($ENV{QUERY_STRING} || '') ne '') {
            $query .= '&' if length $query;
            $query .= $ENV{QUERY_STRING};
        }
    } else {
        $query = $ENV{QUERY_STRING} || '';
    }

    for my $pair (split /&/, $query) {
        next unless length $pair;
        my ($k, $v) = split /=/, $pair, 2;
        $k = _decode($k);
        $v = _decode(defined $v ? $v : '');
        $params{$k} = $v;
    }

    return \%params;
}

sub parse_cookies {
    my %cookies;
    my $raw = $ENV{HTTP_COOKIE} || '';

    for my $pair (split /;\s*/, $raw) {
        next unless length $pair;
        my ($k, $v) = split /=/, $pair, 2;
        next unless defined $k;
        $cookies{$k} = defined $v ? $v : '';
    }

    return \%cookies;
}

sub header_html {
    my (%opt) = @_;
    my @lines = ('Content-Type: text/html; charset=UTF-8');
    push @lines, 'Set-Cookie: ' . $opt{cookie}
        if defined $opt{cookie} && length $opt{cookie};
    return join("\r\n", @lines) . "\r\n\r\n";
}

sub header_json {
    my (%opt) = @_;
    my @lines = ('Content-Type: application/json; charset=UTF-8');
    push @lines, 'Set-Cookie: ' . $opt{cookie}
        if defined $opt{cookie} && length $opt{cookie};
    return join("\r\n", @lines) . "\r\n\r\n";
}

sub make_cookie {
    my (%opt) = @_;
    my $name     = $opt{name}  || 'sid';
    my $value    = defined $opt{value} ? $opt{value} : '';
    my $path     = $opt{path} || '/';
    my $expires  = $opt{expires};
    my $httponly = exists $opt{httponly} ? $opt{httponly} : 1;

    my @parts = ("$name=$value", "Path=$path");
    push @parts, "Expires=$expires" if defined $expires && length $expires;
    push @parts, 'HttpOnly' if $httponly;

    return join('; ', @parts);
}

sub _decode {
    my ($s) = @_;
    $s = '' unless defined $s;
    $s =~ tr/+/ /;
    $s =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
    return $s;
}

1;