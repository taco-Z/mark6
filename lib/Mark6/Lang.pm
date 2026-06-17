package Mark6::Lang;

use strict;
use warnings;
use Mark6::DataStore;

my %DEFAULT_JA = (
    'admin.title'             => '管理画面',
    'admin.nav.dashboard'     => 'ダッシュボード',
    'admin.nav.home'          => 'ホーム',
    'admin.nav.articles'      => '記事',
    'admin.nav.media'         => 'メディア',
    'admin.nav.settings'      => '設定',
    'admin.nav.view_site'     => 'サイト表示',
    'admin.nav.logout'        => 'ログアウト',
    'admin.dashboard.title'   => 'ダッシュボード',
    'admin.dashboard.logged_in_as' => 'ログイン中',
    'admin.dashboard.edit_home'    => 'ホーム編集',
    'admin.dashboard.manage_articles' => '記事管理',
    'admin.dashboard.manage_media'    => 'メディア管理',
    'admin.dashboard.site_settings'   => 'サイト設定',
);

sub new {
    my ($class, %args) = @_;
    my $root = $args{root} || '.';
    my $store = Mark6::DataStore->new(root => $root);
    my $config = $store->read_json('dat', 'config.json') || {};
    my $code = $args{code} || $config->{site}{language} || 'ja';
    $code = 'ja' unless $code =~ /\A[a-z][a-z0-9_-]*\z/i;

    my $strings = $store->read_json('dat', 'lang', "$code.json") || {};
    my %merged = (%DEFAULT_JA, %{$strings});

    return bless {
        code => $code,
        strings => \%merged,
    }, $class;
}

sub code {
    my ($self) = @_;
    return $self->{code};
}

sub t {
    my ($self, $key, $fallback) = @_;
    return $self->{strings}{$key} if exists $self->{strings}{$key};
    return defined $fallback ? $fallback : $key;
}

1;
