package lang;
use strict;
use warnings;
use utf8;
use JSON::PP;
use Exporter 'import';

our @EXPORT_OK = qw(load_dict get_lang t);

my %DICT_CACHE;

sub load_dict {
    my ($file) = @_;
    return $DICT_CACHE{$file} if exists $DICT_CACHE{$file};

    open my $fh, '<:encoding(UTF-8)', $file
        or die "lang.pm: cannot open $file: $!";
    local $/;
    my $json = <$fh>;
    close $fh;

    my $dict = decode_json($json);
    $DICT_CACHE{$file} = $dict;
    return $dict;
}

sub _parse_cookies {
    my ($cookie_header) = @_;
    my %cookies;

    return \%cookies unless defined $cookie_header && length $cookie_header;

    for my $pair (split /\s*;\s*/, $cookie_header) {
        my ($k, $v) = split /=/, $pair, 2;
        next unless defined $k && length $k;
        $v = '' unless defined $v;
        $cookies{$k} = $v;
    }

    return \%cookies;
}

sub _is_valid_lang {
    my ($lang, $dict) = @_;
    return 0 unless defined $lang && length $lang;
    return exists $dict->{$lang};
}

sub get_lang {
    my ($ctx) = @_;

    my $dict   = $ctx->{lang_dict} || {};
    my $params = $ctx->{params}    || {};
    my $env    = $ctx->{env}       || \%ENV;

    # 1. URL parameter
    if (_is_valid_lang($params->{lang}, $dict)) {
        return $params->{lang};
    }

    # 2. Cookie
    my $cookies = _parse_cookies($env->{HTTP_COOKIE});
    if (_is_valid_lang($cookies->{mark6_lang}, $dict)) {
        return $cookies->{mark6_lang};
    }

    # 3. Default
    return 'en';
}

sub t {
    my ($ctx, $key) = @_;
    my $dict = $ctx->{lang_dict} || {};
    my $lang = $ctx->{lang} || 'en';

    return $dict->{$lang}{$key}
        // $dict->{en}{$key}
        // $key;
}

1;
