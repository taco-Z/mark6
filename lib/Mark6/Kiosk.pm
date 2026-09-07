package Mark6::Kiosk;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(config_for_lang item_type valid_url);

sub config_for_lang {
    my ($kiosk, $lang) = @_;
    return {} unless ref($kiosk) eq 'HASH';

    # The original flat structure belongs to Japanese only.
    if (exists $kiosk->{enabled} || exists $kiosk->{items} || exists $kiosk->{mode}) {
        return ($lang || '') eq 'ja' ? $kiosk : {};
    }

    return ref($kiosk->{$lang}) eq 'HASH' ? $kiosk->{$lang} : {};
}

sub item_type {
    my ($item) = @_;
    return '' unless ref($item) eq 'HASH';
    return 'url' if ($item->{type} || '') eq 'url';
    return 'amazon' if ($item->{type} || '') eq 'amazon';
    return 'amazon' if ($item->{keyword} || '') ne '';
    return '';
}

sub valid_url {
    my ($url) = @_;
    return defined($url) && $url =~ m{\Ahttps?://[^\s]+\z}i ? 1 : 0;
}

1;
