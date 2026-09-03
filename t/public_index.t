use strict;
use warnings;
use utf8;
use Test::More;
use File::Path qw(make_path remove_tree);
use File::Spec;
use JSON::PP ();
use Encode qw(decode);

my $perl = $^X;
my $script = File::Spec->catfile('public', 'index.cgi');
my $root = File::Spec->catdir('t', 'tmp_public_index');

remove_tree($root) if -d $root;
make_path(File::Spec->catdir($root, 'dat', 'articles'));

write_json(File::Spec->catfile($root, 'dat', 'config.json'), {
    version => 1,
    site => {
        title => 'MARK6 Test',
        language => 'ja',
        default_lang => 'ja',
        langs => ['ja', 'en'],
        node => 'oita360',
        base_url => '/test/mark6',
    },
    features => {
        tags => JSON::PP::true,
        newest => JSON::PP::true,
        popular => JSON::PP::true,
        ai => JSON::PP::false,
    },
    display => {
        mini_articles => 1,
        articles_per_page => 1,
    },
    kiosk => {
        provider => 'amazon',
        affiliate_tag => 'mark6-test-22',
    },
});

write_json(File::Spec->catfile($root, 'dat', 'home.json'), {
    title => 'ようこそ',
    body => '<p>Home body</p>',
    langs => {
        ja => {
            title => 'ようこそ',
            body => '<p>日本語ホーム</p>',
        },
        en => {
            title => 'Welcome',
            body => '<p>English home</p>',
        },
    },
    show_articles => JSON::PP::true,
    updated_at => '',
});

write_json(File::Spec->catfile($root, 'dat', 'articles', '1375451805.json'), {
    id => '1375451805',
    type => 'article',
    status => 'published',
    default_lang => 'ja',
    node => 'oita360',
    slug => 'beppu-station',
    langs => {
        ja => {
            title => '別府駅',
            description => '<p>別府駅の紹介</p>',
            body => '<p>日本語本文です。</p>',
        },
        en => {
            title => 'Beppu Station',
            description => '<p>About Beppu Station</p>',
            body => '',
        },
    },
    tags => ['News'],
    image => '',
    kiosk => {
        enabled => JSON::PP::true,
        items => [
            {
                label => 'Guide Book',
                keyword => 'travel guide',
            },
            {
                label => 'Local Gift',
                keyword => 'local gift',
            },
        ],
    },
    ai => {
        seo => {
            lang => 'ja',
            seo_description => 'Japanese SEO description',
        },
    },
    created_at => '2013-08-02T13:56:45Z',
});

write_json(File::Spec->catfile($root, 'dat', 'articles', '1375451804.json'), {
    id => '1375451804',
    type => 'article',
    status => 'published',
    default_lang => 'ja',
    node => 'oita360',
    slug => 'older-post',
    langs => {
        ja => {
            title => 'Older Article',
            description => '<p>Older summary</p>',
            body => '<p>Older body</p>',
        },
    },
    tags => ['News'],
    image => 'https://example.com/older.jpg',
    kiosk => {
        enabled => JSON::PP::false,
        items => [
            {
                label => 'Hidden Item',
                keyword => 'hidden item',
            },
        ],
    },
    created_at => '2013-08-02T13:56:44Z',
});

my $home = run_cgi('', '/ja/');
like($home, qr/Content-Type: text\/html; charset=UTF-8/, 'prints UTF-8 content type');
like($home, qr/ようこそ/, 'renders home title');
like($home, qr/日本語ホーム/, 'renders localized Japanese home body');
like($home, qr/別府駅/, 'renders default language article summary');
like($home, qr/href="\/test\/mark6\/ja\/oita360\/beppu-station\/"/, 'renders localized article URL');
like($home, qr/class="language-switch"/, 'renders language switch links');
like($home, qr/href="\/test\/mark6\/assets\/css\/mark6\.css\?v=3"/, 'renders versioned asset URL from asset base');
like($home, qr/mark6-icon\.svg/, 'renders MARK6 favicon');
like($home, qr/mark6-logo-light\.svg/, 'renders MARK6 footer logo');
like($home, qr/href="\/test\/mark6\/ja\/"/, 'renders home URL from site base');
like($home, qr/>ホーム<\/a>/, 'renders Japanese home navigation label');
like($home, qr/>記事<\/a>/, 'renders Japanese articles navigation label');
like($home, qr/<article class="article-summary">/, 'uses a full-width summary layout without an image');
unlike($home, qr/<article class="article-summary has-image">/, 'does not reserve an image column when no image exists');
unlike($home, qr/Older Article/, 'home article list honors mini_articles limit');
like($home, qr/href="\/test\/mark6\/ja\/oita360\/\?tag=News"/, 'home tag URL uses the article node without scanning fallback');

my $detail = run_cgi('order=focus&tar=1375451805');
like($detail, qr/別府駅/, 'renders legacy detail title');
like($detail, qr/日本語本文です。/, 'renders legacy detail body');
like($detail, qr/href="\/test\/mark6\/en\/oita360\/beppu-station\/"/, 'detail links alternate language');
like($detail, qr/<meta name="description" content="Japanese SEO description">/, 'renders the matching language SEO description');
like($detail, qr/<link rel="canonical" href="http:\/\/localhost\/test\/mark6\/ja\/oita360\/beppu-station\/">/, 'renders article canonical URL');
like($detail, qr/<meta property="og:type" content="article">/, 'renders article Open Graph type');
like($detail, qr/<section class="kiosk">/, 'renders kiosk section when enabled');
like($detail, qr/>売店<\/h2>/, 'renders Japanese kiosk heading');
like($detail, qr/class="kiosk-card"/, 'renders kiosk card links');
like($detail, qr/<span class="kiosk-label">Guide Book<\/span>/, 'renders kiosk item label');
like($detail, qr/<span class="kiosk-keyword">検索: travel guide<\/span>/, 'renders kiosk keyword note');
like($detail, qr/<span class="kiosk-action">Amazonで探す<\/span>/, 'renders Japanese kiosk action label');
like($detail, qr{href="https://www\.amazon\.co\.jp/s\?k=travel%20guide&amp;tag=mark6-test-22"}, 'renders encoded Amazon kiosk URL with affiliate tag');

my $en_detail = run_cgi('', '/en/oita360/beppu-station/');
like($en_detail, qr/Beppu Station/, 'renders English detail title from path URL');
like($en_detail, qr/>Home<\/a>/, 'renders English home navigation label');
like($en_detail, qr/>Articles<\/a>/, 'renders English articles navigation label');
like($en_detail, qr/<meta name="description" content="About Beppu Station">/, 'uses localized content when no matching language SEO description exists');
unlike($en_detail, qr/Japanese SEO description/, 'does not use a different language SEO description');
like($en_detail, qr/>Kiosk<\/h2>/, 'renders English kiosk heading');
like($en_detail, qr/<span class="kiosk-action">Search Amazon<\/span>/, 'renders English kiosk action label');
my $request_uri_detail = run_cgi('', '', '/public/index.cgi/en/oita360/beppu-station/?x=1');
like($request_uri_detail, qr/Beppu Station/, 'falls back to REQUEST_URI and strips public/index.cgi');

my $node_top = run_cgi('', '/ja/oita360/');
like($node_top, qr/class="article-list"/, 'renders node top article list');
unlike($node_top, qr/Older Article/, 'node article list honors articles_per_page');
like($node_top, qr/href="\/test\/mark6\/ja\/oita360\/\?page=2"/, 'node article list links to page 2');
my $node_page_2 = run_cgi('page=2', '/ja/oita360/');
like($node_page_2, qr/Older Article/, 'node article list renders page 2');

my $lang_top = run_cgi('', '/ja/');
like($lang_top, qr/日本語ホーム/, 'renders language top');
like($lang_top, qr/Set-Cookie: mark6_lang=ja; Path=\/test\/mark6\/; Max-Age=31536000; SameSite=Lax/, 'language page stores language cookie');
my $en_home = run_cgi('', '/en/');
like($en_home, qr/Welcome/, 'renders English home title');
like($en_home, qr/English home/, 'renders English home body');

my $root_top = run_cgi('', '/', '', 'en-US,en;q=0.9');
like($root_top, qr/Status: 302 Found/, 'root redirects to initial language');
like($root_top, qr/Location: \/test\/mark6\/en\//, 'root redirects to English from browser language');

my $root_cookie = run_cgi('', '/', '', 'en-US,en;q=0.9', 'mark6_lang=ja');
like($root_cookie, qr/Location: \/test\/mark6\/ja\//, 'root redirect prefers language cookie');

my $root_ja = run_cgi('path=', '', '', 'ja-JP,ja;q=0.9,en;q=0.8');
like($root_ja, qr/Location: \/test\/mark6\/ja\//, 'empty path query redirects to Japanese from browser language');

my $robots = run_cgi('', '/robots.txt');
like($robots, qr/Content-Type: text\/plain; charset=UTF-8/, 'renders robots text');
like($robots, qr/Sitemap: http:\/\/localhost\/test\/mark6\/sitemap\.xml/, 'robots links the sitemap');

my $sitemap = run_cgi('', '/sitemap.xml');
like($sitemap, qr/Content-Type: application\/xml; charset=UTF-8/, 'renders XML sitemap');
like($sitemap, qr/http:\/\/localhost\/test\/mark6\/ja\/oita360\/beppu-station\//, 'sitemap includes Japanese article URL');
like($sitemap, qr/http:\/\/localhost\/test\/mark6\/en\/oita360\/beppu-station\//, 'sitemap includes English article URL');

my $request_uri_lang = run_cgi('', '', '/test/mark6/ja/');
unlike($request_uri_lang, qr/Status: 302 Found/, 'language URL from REQUEST_URI is not redirected');
like($request_uri_lang, qr/日本語ホーム/, 'language URL from REQUEST_URI renders normally');

my $unsupported_lang = run_cgi('', '/fr/oita360/beppu-station/');
like($unsupported_lang, qr/<html lang="ja">/, 'unsupported language falls back to default language');
like($en_detail, qr/日本語本文です。/, 'falls back to default body when untranslated');

my $list = run_cgi('order=article&tag=News');
like($list, qr/Tag: News/, 'renders tag page');
ok(-e File::Spec->catfile($root, 'dat', 'logs', 'access.jsonl'), 'writes privacy-minimized access log');
like($list, qr/href="\/test\/mark6\/ja\/oita360\/\?tag=News"/, 'renders tag URL from site base');
like($list, qr/別府駅/, 'renders filtered article');
unlike($list, qr/Older Article/, 'tag page honors articles_per_page');
my $list_page_2 = run_cgi('order=article&tag=News&page=2');
like($list_page_2, qr/Older Article/, 'tag page renders page 2');

my $disabled_kiosk = run_cgi('', '/ja/oita360/older-post/');
unlike($disabled_kiosk, qr/Hidden Item/, 'does not render disabled kiosk items');

remove_tree($root);
done_testing;

sub run_cgi {
    my ($query, $path_info, $request_uri, $accept_language, $cookie) = @_;
    local $ENV{QUERY_STRING} = $query;
    local $ENV{PATH_INFO} = $path_info || '';
    local $ENV{REQUEST_URI} = $request_uri || '';
    local $ENV{HTTP_ACCEPT_LANGUAGE} = $accept_language || '';
    local $ENV{HTTP_COOKIE} = $cookie || '';
    local $ENV{REQUEST_METHOD} = 'GET';
    local $ENV{MARK6_ROOT} = $root;

    my $output = `$perl $script`;
    my $exit = $? >> 8;
    die "CGI failed with exit $exit" if $exit;
    return decode('UTF-8', $output);
}

sub write_json {
    my ($path, $data) = @_;
    open my $fh, '>:raw', $path or die "Cannot write $path: $!";
    print {$fh} JSON::PP->new->utf8->canonical->pretty->encode($data);
    close $fh;
}
