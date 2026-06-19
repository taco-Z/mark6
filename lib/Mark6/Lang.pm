package Mark6::Lang;

use strict;
use warnings;
use utf8;
use Mark6::DataStore;

my %DEFAULTS = (
    ja => {
        'admin.title'                    => '管理画面',
        'admin.nav.dashboard'            => 'ダッシュボード',
        'admin.nav.home'                 => 'ホーム',
        'admin.nav.articles'             => '記事',
        'admin.nav.media'                => 'メディア',
        'admin.nav.settings'             => '設定',
        'admin.nav.view_site'            => 'サイト表示',
        'admin.nav.logout'               => 'ログアウト',
        'admin.dashboard.title'          => 'ダッシュボード',
        'admin.dashboard.logged_in_as'   => 'ログイン中',
        'admin.dashboard.edit_home'      => 'ホーム編集',
        'admin.dashboard.manage_articles' => '記事管理',
        'admin.dashboard.manage_media'   => 'メディア管理',
        'admin.dashboard.site_settings'  => 'サイト設定',

        'admin.common.dashboard'         => 'ダッシュボード',
        'admin.common.home'              => 'ホーム',
        'admin.common.articles'          => '記事',
        'admin.common.media'             => 'メディア',
        'admin.common.settings'          => '設定',
        'admin.common.view'              => '表示',
        'admin.common.edit'              => '編集',
        'admin.common.delete'            => '削除',
        'admin.common.save'              => '保存',
        'admin.common.upload'            => 'アップロード',
        'admin.common.not_found'         => '見つかりません',
        'admin.common.csrf_error'        => 'CSRFエラー',
        'admin.common.invalid_form_token' => 'フォームトークンが無効です。',

        'admin.article.title'            => '記事',
        'admin.article.new'              => '新規記事',
        'admin.article.edit'             => '記事編集',
        'admin.article.empty'            => '記事はまだありません。',
        'admin.article.not_found'        => '記事が見つかりません。',
        'admin.article.save_error'       => '保存エラー',
        'admin.article.delete_error'     => '削除エラー',
        'admin.article.confirm_delete'   => 'この記事を削除しますか？',
        'admin.article.default_lang'     => '標準言語',
        'admin.article.node'             => 'セクション',
        'admin.article.slug'             => 'URL名',
        'admin.article.status'           => '公開状態',
        'admin.article.status_draft'     => '下書き',
        'admin.article.status_published' => '公開',
        'admin.article.tags'             => 'タグ',
        'admin.article.main_image'       => 'メイン画像',
        'admin.article.no_image'         => '画像なし',
        'admin.article.image_path'       => '画像パス',
        'admin.article.field_title'      => 'タイトル',
        'admin.article.field_description_html' => '説明HTML',
        'admin.article.field_body_html'  => '本文HTML',

        'admin.home.saved'               => 'ホームを保存しました。',
        'admin.home.title_label'         => 'タイトル',
        'admin.home.body_html'           => '本文HTML',
        'admin.home.show_latest'         => 'ホームに最新記事を表示',
        'admin.home.save'                => 'ホームを保存',

        'admin.media.empty'              => 'メディアはまだありません。',
        'admin.media.image_file'         => '画像ファイル',
        'admin.media.path'               => 'パス',
        'admin.media.html'               => 'HTML',
        'admin.media.bytes'              => 'バイト',
        'admin.media.upload_error'       => 'アップロードエラー',
        'admin.media.delete_error'       => '削除エラー',
        'admin.media.confirm_delete'     => 'このメディアファイルを削除しますか？',

        'admin.settings.saved'           => '設定を保存しました。',
        'admin.settings.site'            => 'サイト',
        'admin.settings.site_title'      => 'サイト名',
        'admin.settings.base_url'        => 'ベースURL',
        'admin.settings.language'        => '言語',
        'admin.settings.display'         => '表示',
        'admin.settings.articles_per_page' => '1ページの記事数',
        'admin.settings.mini_articles'   => 'ミニ記事数',
        'admin.settings.features'        => '機能',
        'admin.settings.tags'            => 'タグ',
        'admin.settings.newest_list'     => '新着リスト',
        'admin.settings.popular_list'    => '人気リスト',
        'admin.settings.shop'            => 'ショップ',
        'admin.settings.ai_assist'       => 'AI支援',
        'admin.settings.shop_title'      => 'ショップ名',
        'admin.settings.paypal_id'       => 'PayPal ID',
        'admin.settings.save'            => '設定を保存',

        'admin.lang.ja'                  => '日本語',
        'admin.lang.en'                  => '英語',

        'admin.login.title'              => 'MARK6 ログイン',
        'admin.login.failed'             => 'ログインに失敗しました。',
        'admin.login.user_id'            => 'ユーザーID',
        'admin.login.password'           => 'パスワード',
        'admin.login.submit'             => 'ログイン',

        'admin.setup.title'              => 'MARK6 初期設定',
        'admin.setup.site_title'         => 'サイト名',
        'admin.setup.language'           => '言語',
        'admin.setup.user_id'            => '管理ユーザーID',
        'admin.setup.password'           => 'パスワード',
        'admin.setup.password_confirm'   => 'パスワード確認',
        'admin.setup.submit'             => 'MARK6を開始',
        'admin.setup.error_site_title'   => 'サイト名を入力してください。',
        'admin.setup.error_user_id'      => 'ユーザーIDを入力してください。',
        'admin.setup.error_password'     => 'パスワードを入力してください。',
        'admin.setup.error_password_confirm' => 'パスワード確認が一致しません。',
        'admin.setup.error_password_length' => 'パスワードは8文字以上にしてください。',
        'admin.setup.error_language'     => '言語は ja または en を選択してください。',
    },
    en => {
        'admin.title'                    => 'Admin',
        'admin.nav.dashboard'            => 'Dashboard',
        'admin.nav.home'                 => 'Home',
        'admin.nav.articles'             => 'Articles',
        'admin.nav.media'                => 'Media',
        'admin.nav.settings'             => 'Settings',
        'admin.nav.view_site'            => 'View Site',
        'admin.nav.logout'               => 'Logout',
        'admin.dashboard.title'          => 'Dashboard',
        'admin.dashboard.logged_in_as'   => 'Logged in as',
        'admin.dashboard.edit_home'      => 'Edit Home',
        'admin.dashboard.manage_articles' => 'Manage Articles',
        'admin.dashboard.manage_media'   => 'Manage Media',
        'admin.dashboard.site_settings'  => 'Site Settings',

        'admin.common.dashboard'         => 'Dashboard',
        'admin.common.home'              => 'Home',
        'admin.common.articles'          => 'Articles',
        'admin.common.media'             => 'Media',
        'admin.common.settings'          => 'Settings',
        'admin.common.view'              => 'View',
        'admin.common.edit'              => 'Edit',
        'admin.common.delete'            => 'Delete',
        'admin.common.save'              => 'Save',
        'admin.common.upload'            => 'Upload',
        'admin.common.not_found'         => 'Not Found',
        'admin.common.csrf_error'        => 'CSRF Error',
        'admin.common.invalid_form_token' => 'Invalid form token.',

        'admin.article.title'            => 'Articles',
        'admin.article.new'              => 'New Article',
        'admin.article.edit'             => 'Edit Article',
        'admin.article.empty'            => 'No articles yet.',
        'admin.article.not_found'        => 'Article not found.',
        'admin.article.save_error'       => 'Save Error',
        'admin.article.delete_error'     => 'Delete Error',
        'admin.article.confirm_delete'   => 'Delete this article?',
        'admin.article.default_lang'     => 'Default language',
        'admin.article.node'             => 'Section',
        'admin.article.slug'             => 'URL slug',
        'admin.article.status'           => 'Status',
        'admin.article.status_draft'     => 'Draft',
        'admin.article.status_published' => 'Published',
        'admin.article.tags'             => 'Tags',
        'admin.article.main_image'       => 'Main image',
        'admin.article.no_image'         => 'No image',
        'admin.article.image_path'       => 'Image path',
        'admin.article.field_title'      => 'Title',
        'admin.article.field_description_html' => 'Description HTML',
        'admin.article.field_body_html'  => 'Body HTML',

        'admin.home.saved'               => 'Home saved.',
        'admin.home.title_label'         => 'Title',
        'admin.home.body_html'           => 'Body HTML',
        'admin.home.show_latest'         => 'Show latest articles on home',
        'admin.home.save'                => 'Save Home',

        'admin.media.empty'              => 'No media yet.',
        'admin.media.image_file'         => 'Image file',
        'admin.media.path'               => 'Path',
        'admin.media.html'               => 'HTML',
        'admin.media.bytes'              => 'bytes',
        'admin.media.upload_error'       => 'Upload Error',
        'admin.media.delete_error'       => 'Delete Error',
        'admin.media.confirm_delete'     => 'Delete this media file?',

        'admin.settings.saved'           => 'Settings saved.',
        'admin.settings.site'            => 'Site',
        'admin.settings.site_title'      => 'Site title',
        'admin.settings.base_url'        => 'Base URL',
        'admin.settings.language'        => 'Language',
        'admin.settings.display'         => 'Display',
        'admin.settings.articles_per_page' => 'Articles per page',
        'admin.settings.mini_articles'   => 'Mini articles',
        'admin.settings.features'        => 'Features',
        'admin.settings.tags'            => 'Tags',
        'admin.settings.newest_list'     => 'Newest list',
        'admin.settings.popular_list'    => 'Popular list',
        'admin.settings.shop'            => 'Shop',
        'admin.settings.ai_assist'       => 'AI assist',
        'admin.settings.shop_title'      => 'Shop title',
        'admin.settings.paypal_id'       => 'PayPal ID',
        'admin.settings.save'            => 'Save Settings',

        'admin.lang.ja'                  => 'Japanese',
        'admin.lang.en'                  => 'English',

        'admin.login.title'              => 'MARK6 Login',
        'admin.login.failed'             => 'Login failed.',
        'admin.login.user_id'            => 'User ID',
        'admin.login.password'           => 'Password',
        'admin.login.submit'             => 'Login',

        'admin.setup.title'              => 'MARK6 Setup',
        'admin.setup.site_title'         => 'Site title',
        'admin.setup.language'           => 'Language',
        'admin.setup.user_id'            => 'Admin user ID',
        'admin.setup.password'           => 'Password',
        'admin.setup.password_confirm'   => 'Password confirmation',
        'admin.setup.submit'             => 'Start MARK6',
        'admin.setup.error_site_title'   => 'Site title is required.',
        'admin.setup.error_user_id'      => 'User ID is required.',
        'admin.setup.error_password'     => 'Password is required.',
        'admin.setup.error_password_confirm' => 'Password confirmation does not match.',
        'admin.setup.error_password_length' => 'Password must be at least 8 characters.',
        'admin.setup.error_language'     => 'Language must be ja or en.',
    },
);

sub new {
    my ($class, %args) = @_;
    my $root = $args{root} || '.';
    my $store = Mark6::DataStore->new(root => $root);
    my $config = $store->read_json('dat', 'config.json') || {};
    my $code = $args{code} || $config->{site}{language} || 'ja';
    $code = 'ja' unless exists $DEFAULTS{$code};

    my $strings = $store->read_json('dat', 'lang', "$code.json") || {};
    my %merged = (%{$DEFAULTS{$code}}, %{$strings});

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
