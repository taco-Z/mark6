use strict;
use warnings;
use utf8;
use Test::More;
use File::Path qw(make_path remove_tree);
use File::Spec;
use JSON::PP ();
use Encode qw(decode encode);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);

my $perl = $^X;
my $root = File::Spec->catdir('t', 'tmp_admin_pages_navigation');
remove_tree($root) if -d $root;
make_path(File::Spec->catdir($root, 'dat', 'sessions'));
make_path(File::Spec->catdir($root, 'dat', 'articles'));

write_json(File::Spec->catfile($root, 'dat', 'users.json'), { version => 1, users => [] });
write_json(File::Spec->catfile($root, 'dat', 'config.json'), {
    version => 1,
    site => { title => 'MARK6 Test', language => 'ja', default_lang => 'ja', langs => ['ja', 'en'], base_url => '/mark6' },
    features => { ai => JSON::PP::false },
    display => { articles_per_page => 20, mini_articles => 15 },
    kiosk => { provider => 'amazon', affiliate_tag => '' },
});
write_json(File::Spec->catfile($root, 'dat', 'home.json'), { title => 'Home', body => '', show_articles => JSON::PP::true });
write_json(File::Spec->catfile($root, 'dat', 'articles', 'article-one.json'), {
    id => 'article-one', type => 'article', status => 'published', node => 'news', slug => 'article-one',
    default_lang => 'ja', langs => { ja => { title => '通常記事', description => '', body => '本文' } },
});

my $create = `$perl tools/create_user.pl --root "$root" --name admin --password secret --rank master`;
is($? >> 8, 0, 'create_user exits ok');
my $login = run_cgi(script => File::Spec->catfile('admin', 'login.cgi'), method => 'POST', body => form_data(name => 'admin', password => 'secret'));
my ($session_id) = $login =~ /mark6_session=([0-9a-f]{64})/;
ok($session_id, 'login sets session');

my $new_page = run_cgi(
    script => File::Spec->catfile('admin', 'pages.cgi'), method => 'GET',
    query => 'command=new', cookie => "mark6_session=$session_id",
);
like($new_page, qr/固定ページを作成/, 'Pages uses localized page heading');
like($new_page, qr/action="pages\.cgi"/, 'Pages reuses editor with its own action');
unlike($new_page, qr/<label>セクションID<br>/, 'fixed-page editor does not ask for a section');
my ($page_csrf) = $new_page =~ /name="csrf_token" value="([0-9a-f]+)"/;
ok($page_csrf, 'Pages form includes csrf token');

my $save_page = run_cgi(
    script => File::Spec->catfile('admin', 'pages.cgi'), method => 'POST', cookie => "mark6_session=$session_id",
    body => form_data(
        command => 'save', csrf_token => $page_csrf, id => 'about-page', default_lang => 'ja',
        slug => 'about', status => 'published', title_ja => 'このサイトについて', body_ja => '<p>固定ページ本文</p>',
        title_en => 'About', body_en => '<p>English page</p>',
    ),
);
like($save_page, qr/Location: pages\.cgi/, 'saving a page returns to Pages');
my $page_data = read_json(File::Spec->catfile($root, 'dat', 'articles', 'about-page.json'));
is($page_data->{type}, 'page', 'saved content has page type');
is($page_data->{slug}, 'about', 'saved page keeps slug');

my $pages = run_cgi(script => File::Spec->catfile('admin', 'pages.cgi'), method => 'GET', cookie => "mark6_session=$session_id");
like($pages, qr/このサイトについて/, 'Pages list includes fixed page');
unlike($pages, qr/通常記事/, 'Pages list excludes articles');
my $articles = run_cgi(script => File::Spec->catfile('admin', 'articles.cgi'), method => 'GET', cookie => "mark6_session=$session_id");
like($articles, qr/通常記事/, 'Articles list includes article');
unlike($articles, qr/このサイトについて/, 'Articles list excludes fixed page');

my $navigation = run_cgi(script => File::Spec->catfile('admin', 'navigation.cgi'), method => 'GET', cookie => "mark6_session=$session_id");
like($navigation, qr/ヘッダーナビゲーション/, 'Navigation renders header settings');
like($navigation, qr/フッターナビゲーション/, 'Navigation renders footer settings on same page');
like($navigation, qr/name="header_ja_label_1"/, 'Navigation renders Japanese header fields');
like($navigation, qr/name="footer_en_url_1"/, 'Navigation renders English footer fields');
my ($nav_csrf) = $navigation =~ /name="csrf_token" value="([0-9a-f]+)"/;
ok($nav_csrf, 'Navigation form includes csrf token');

my $save_navigation = run_cgi(
    script => File::Spec->catfile('admin', 'navigation.cgi'), method => 'POST', cookie => "mark6_session=$session_id",
    body => form_data(
        csrf_token => $nav_csrf,
        header_ja_enabled_1 => 1, header_ja_label_1 => 'このサイトについて', header_ja_url_1 => '/about/',
        header_en_enabled_1 => 1, header_en_label_1 => 'About', header_en_url_1 => '/en/about/',
        footer_ja_enabled_1 => 1, footer_ja_label_1 => 'お問い合わせ', footer_ja_url_1 => '/contact/',
        footer_en_label_1 => 'Hidden contact', footer_en_url_1 => '/en/contact/',
    ),
);
like($save_navigation, qr/Location: navigation\.cgi\?saved=1/, 'Navigation save redirects');
my $config = read_json(File::Spec->catfile($root, 'dat', 'config.json'));
is($config->{navigation}{header}{ja}[0]{url}, '/about/', 'Japanese header URL saved');
is($config->{navigation}{header}{en}[0]{label}, 'About', 'English header label saved');
ok(!$config->{navigation}{footer}{en}[0]{enabled}, 'unchecked navigation item is saved disabled');

remove_tree($root);
done_testing;

sub run_cgi {
    my (%args) = @_;
    local $ENV{MARK6_ROOT} = $root;
    local $ENV{MARK6_CONTENT_TYPE};
    local $ENV{REQUEST_METHOD} = $args{method} || 'GET';
    local $ENV{QUERY_STRING} = $args{query} || '';
    local $ENV{PATH_INFO} = $args{path_info} || '';
    local $ENV{HTTP_COOKIE} = $args{cookie} || '';
    local $ENV{CONTENT_TYPE} = 'application/x-www-form-urlencoded';
    my $body = $args{body} || '';
    local $ENV{CONTENT_LENGTH} = length($body);
    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, $perl, $args{script});
    print {$in} $body if $body ne '';
    close $in;
    my $output = do { local $/; <$out> };
    my $error = do { local $/; <$err> };
    waitpid($pid, 0);
    die $error if ($? >> 8) != 0;
    return decode('UTF-8', $output || '');
}

sub form_data {
    my (%pairs) = @_;
    return join '&', map { url_encode($_) . '=' . url_encode($pairs{$_}) } sort keys %pairs;
}

sub url_encode {
    my ($value) = @_;
    $value = encode('UTF-8', defined $value ? $value : '');
    $value =~ s/([^A-Za-z0-9_.~-])/sprintf('%%%02X', ord($1))/eg;
    return $value;
}

sub write_json {
    my ($path, $data) = @_;
    open my $fh, '>:raw', $path or die "Cannot write $path: $!";
    print {$fh} JSON::PP->new->utf8->canonical->pretty->encode($data);
    close $fh;
}

sub read_json {
    my ($path) = @_;
    open my $fh, '<:raw', $path or die "Cannot read $path: $!";
    local $/;
    my $body = <$fh>;
    close $fh;
    return JSON::PP->new->utf8->decode($body);
}

