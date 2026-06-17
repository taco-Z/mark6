package Mark6::CGI;

use strict;
use warnings;
use Encode qw(decode encode);

sub request_params {
    my %params = query_params($ENV{QUERY_STRING} || '');

    if (($ENV{REQUEST_METHOD} || 'GET') eq 'POST') {
        my $length = $ENV{CONTENT_LENGTH} || 0;
        read(STDIN, my $body, $length) if $length > 0;
        %params = (%params, query_params($body || ''));
    }

    return %params;
}

sub query_params {
    my ($query) = @_;
    my %params;

    for my $pair (split /[&;]/, $query || '') {
        next if $pair eq '';
        my ($key, $value) = split /=/, $pair, 2;
        $key = url_decode($key || '');
        $value = url_decode($value || '');
        $params{$key} = $value;
    }

    return %params;
}

sub cookies {
    my %cookies;

    for my $pair (split /;\s*/, $ENV{HTTP_COOKIE} || '') {
        next if $pair eq '';
        my ($key, $value) = split /=/, $pair, 2;
        $cookies{$key || ''} = $value || '';
    }

    return %cookies;
}

sub url_decode {
    my ($value) = @_;
    $value =~ tr/+/ /;
    $value =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
    return decode('UTF-8', $value);
}

sub url_encode {
    my ($value) = @_;
    $value = encode('UTF-8', $value || '');
    $value =~ s/([^A-Za-z0-9_.~-])/sprintf('%%%02X', ord($1))/eg;
    return $value;
}

sub escape_html {
    my ($value) = @_;
    $value = '' unless defined $value;
    $value =~ s/&/&amp;/g;
    $value =~ s/</&lt;/g;
    $value =~ s/>/&gt;/g;
    $value =~ s/"/&quot;/g;
    $value =~ s/'/&#39;/g;
    return $value;
}

sub print_html {
    my ($html, @headers) = @_;
    print join("\n", @headers), "\n" if @headers;
    print "Content-Type: text/html; charset=UTF-8\n\n";
    print encode('UTF-8', $html);
}

sub redirect {
    my ($location, @headers) = @_;
    print join("\n", @headers), "\n" if @headers;
    print "Status: 302 Found\n";
    print "Location: $location\n";
    print "Content-Type: text/plain; charset=UTF-8\n\n";
    print "Redirecting to $location\n";
}

1;

