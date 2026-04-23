package lang;
use strict;
use warnings;
use utf8;

use JSON::PP ();

my %CACHE;

sub detect_lang {
    my (%args) = @_;

    my $query_params = $args{query_params} || {};
    my $cookies      = $args{cookies} || {};
    my $default_lang = $args{default_lang} || 'en';

    if (_is_supported_lang($query_params->{lang})) {
        return $query_params->{lang};
    }

    if (_is_supported_lang($cookies->{mark6_lang})) {
        return $cookies->{mark6_lang};
    }

    return $default_lang;
}

sub load_dict {
    my ($base_dir, $lang) = @_;

    $lang = _is_supported_lang($lang) ? $lang : 'en';

    my $cache_key = join "\0", ($base_dir || ''), $lang;
    return $CACHE{$cache_key} if exists $CACHE{$cache_key};

    my $path = $base_dir . "/dat/lang/$lang.json";
    my $dict = _read_lang_file($path, $lang);

    if (!%{$dict} && $lang ne 'en') {
        my $fallback = _read_lang_file($base_dir . '/dat/lang/en.json', 'en');
        $dict = $fallback if %{$fallback};
    }

    if (!%{$dict}) {
        $dict = _default_dict($lang);
    }

    $CACHE{$cache_key} = $dict;
    return $dict;
}

sub text {
    my ($ctx, $key) = @_;

    return '' unless defined $key;

    my $dict = $ctx->{dict} || {};
    return exists $dict->{$key} ? $dict->{$key} : $key;
}

sub _read_lang_file {
    my ($path, $lang) = @_;

    return {} unless defined $path && -f $path;

    open my $fh, '<:encoding(UTF-8)', $path
        or return {};
    local $/;
    my $raw = <$fh>;
    close $fh;

    return {} unless defined $raw && $raw =~ /\S/;

    my $data = _decode_json($raw);
    if (!$data && $raw !~ /^\s*\{/) {
        $data = _decode_json("{\n$raw\n}");
    }

    return _normalize_dict($data, $lang);
}

sub _decode_json {
    my ($raw) = @_;
    return eval { JSON::PP::decode_json($raw) };
}

sub _normalize_dict {
    my ($data, $lang) = @_;

    return {} unless ref $data eq 'HASH';

    if (ref $data->{$lang} eq 'HASH') {
        return $data->{$lang};
    }

    return $data;
}

sub _is_supported_lang {
    my ($lang) = @_;
    return defined $lang && $lang =~ /^(?:ja|en)$/ ? 1 : 0;
}

sub _default_dict {
    my ($lang) = @_;

    my %en = (
        site_title      => 'MARK6',
        login_title     => 'Login',
        login_button    => 'Login',
        logout_label    => 'Logout',
        user_id         => 'User ID',
        password        => 'Password',
        login_failed    => 'Login failed.',
        article_list    => 'Article List',
        article_edit    => 'Article Edit',
        article_new     => 'New Article',
        title_label     => 'Title',
        category_label  => 'Category',
        body_label      => 'Body',
        status_label    => 'Status',
        save_button     => 'Save',
        back_label      => 'Back',
        empty_articles  => 'No articles yet.',
        public_status   => 'Public',
        draft_status    => 'Draft',
    );

    my %ja = (
        site_title      => 'MARK6',
        login_title     => 'Roguin',
        login_button    => 'Roguin',
        logout_label    => 'Roguauto',
        user_id         => 'Yuza ID',
        password        => 'Pasuwado',
        login_failed    => 'Roguin ni shippai shimashita.',
        article_list    => 'Kiji Ichiran',
        article_edit    => 'Kiji Henshu',
        article_new     => 'Shinki Kiji',
        title_label     => 'Taitoru',
        category_label  => 'Kategori',
        body_label      => 'Honbun',
        status_label    => 'Status',
        save_button     => 'Hozon',
        back_label      => 'Modoru',
        empty_articles  => 'Kiji wa mada arimasen.',
        public_status   => 'Kokai',
        draft_status    => 'Shitagaki',
    );

    return $lang eq 'ja' ? \%ja : \%en;
}

1;
