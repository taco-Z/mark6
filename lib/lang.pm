package lang;
use strict;
use warnings;
use utf8;

use JSON::PP ();
use Encode qw(decode FB_CROAK);

sub get_lang {
    my ($ctx) = @_;
    my $lang = $ctx->{params}->{lang}
        || $ctx->{cookies}->{lang}
        || 'en';

    return ($lang eq 'ja' || $lang eq 'en') ? $lang : 'en';
}

sub load_lang {
    my ($ctx, $lang) = @_;
    $lang ||= 'en';

    my $file = $ctx->{path}->{dat_dir} . "/lang/$lang.json";
    my $data = {};

    unless (-f $file) {
        warn "[lang.pm] file not found: $file";
        return $data;
    }

    open my $fh, '<:raw', $file or do {
        warn "[lang.pm] open error: $file : $!";
        return $data;
    };

    local $/;
    my $raw = <$fh>;
    close $fh;

    unless (defined $raw) {
        warn "[lang.pm] read error: $file";
        return $data;
    }

    $raw =~ s/^\xEF\xBB\xBF//;

    my $text = eval { decode('UTF-8', $raw, FB_CROAK) };
    if ($@) {
        warn "[lang.pm] UTF-8 decode error: $file : $@";
        return $data;
    }

    my $json = eval { JSON::PP->new->utf8(0)->decode($text || '{}') };
    if ($@ || ref($json) ne 'HASH') {
        warn "[lang.pm] JSON decode error: $file : $@";
        return $data;
    }

    return $json;

    warn "[lang] requested lang=$lang";

    my $file = $ctx->{path}->{dat_dir} . "/lang/$lang.json";
    warn "[lang] file=$file exists=" . (-f $file ? 1 : 0);

    # いったんキャッシュ無効
    # return $CACHE{$lang} if exists $CACHE{$lang};

    open my $fh, '<:raw', $file or do {
        warn "[lang] open failed: $file : $!";
        return {};
    };

    local $/;
    my $raw = <$fh>;
    close $fh;

    warn "[lang] bytes=" . length($raw // '');

    $raw =~ s/^\xEF\xBB\xBF//;

    my $text = eval { decode('UTF-8', $raw, FB_CROAK) };
    if ($@) {
        warn "[lang] utf8 decode failed: $@";
        return {};
    }

    my $json = eval { JSON::PP->new->utf8(0)->decode($text || '{}') };
    if ($@ || ref($json) ne 'HASH') {
        warn "[lang] json decode failed: $@";
        return {};
    }

    warn "[lang] loaded keys=" . join(',', sort keys %$json);
    return $json;

}

sub t {
    my ($ctx, $key) = @_;
    my $lang = get_lang($ctx);
    my $dict = load_lang($ctx, $lang);
    return $dict->{$key} // $key;
}

1;
