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
    nodes => {
        oita360 => {
            nav => JSON::PP::true,
            labels => {
                ja => '大分360',
                en => 'Oita 360',
            },
        },
        articles => {
            nav => JSON::PP::true,
            labels => {
                ja => '記事セクション',
                en => 'Article section',
            },
        },
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
    kiosk => {
        enabled => JSON::PP::true,
        mode => 'manual',
        items => [
            {
                label => 'Home Guide',
                keyword => 'Oita travel guide',
            },
        ],
    },
    updated_at => '',
});

write_json(File::Spec->catfile($root, 'dat', 'articles', '1375451805.json'), {
    id => '1375451805',
    type => 'article',
    status => 'published',
    default_lang => 'ja',
    node => 'oita360',
    slug => 'beppu-station',
    article => {
        series => 'オオイタビ',
        series_langs => {
            ja => 'オオイタビ',
            en => 'Oita Travel',
        },
        type => 'spot',
        type_langs => {
            ja => 'スポット',
            en => 'Spot',
        },
        location => {
            city => '別府市',
            city_langs => {
                ja => '別府市',
                en => 'Beppu',
            },
        },
    },
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
    tag_langs => {
        ja => ['ニュース'],
        en => ['News'],
    },
    image => '',
    sort_order => 10,
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

write_json(File::Spec->catfile($root, 'dat', 'articles', '1375451806.json'), {
    id => '1375451806',
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
    tag_langs => {
        ja => ['ニュース'],
        en => ['News'],
    },
    image => 'https://example.com/older.jpg',
    sort_order => 20,
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

write_json(File::Spec->catfile($root, 'dat', 'articles', '1375451807.json'), {
    id => '1375451807',
    type => 'article',
    status => 'published',
    default_lang => 'ja',
    node => 'oita360',
    slug => 'nested-tags',
    langs => {
        ja => {
            title => '入れ子タグ',
            description => '<p>日本語</p>',
            body => '<p>日本語本文</p>',
            tags => ['日本語タグ'],
        },
        en => {
            title => 'Nested tags',
            description => '<p>English</p>',
            body => '<p>English body</p>',
            tags => ['Nested EN', 'Travel Tips'],
        },
    },
    tags => ['日本語タグ'],
    image => '',
    sort_order => 30,
    created_at => '2013-08-02T13:56:43Z',
});

my $home = run_cgi('', '/ja/');
like($home, qr/Content-Type: text\/html; charset=UTF-8/, 'prints UTF-8 content type');
like($home, qr/ようこそ/, 'renders home title');
like($home, qr/日本語ホーム/, 'renders localized Japanese home body');
like($home, qr/<span class="kiosk-label">Home Guide<\/span>/, 'renders manual home Kiosk item');
like($home, qr/別府駅/, 'renders default language article summary');
like($home, qr/<div class="summary-taxonomy"><span>オオイタビ<\/span><span>別府市<\/span><span>スポット<\/span><\/div>/, 'renders Japanese localized article taxonomy');
like($home, qr/href="\/test\/mark6\/ja\/oita360\/beppu-station\/"/, 'renders localized article URL');
like($home, qr/class="language-switch"/, 'renders language switch links');
like($home, qr/href="\/test\/mark6\/assets\/css\/mark6\.css\?v=6"/, 'renders versioned asset URL from asset base');
like($home, qr/mark6-icon\.svg/, 'renders MARK6 favicon');
like($home, qr/mark6-logo-light\.svg/, 'renders MARK6 footer logo');
like($home, qr/href="\/test\/mark6\/ja\/"/, 'renders home URL from site base');
like($home, qr/>ホーム<\/a>/, 'renders Japanese home navigation label');
like($home, qr/>記事<\/a>/, 'renders Japanese articles navigation label');
like($home, qr/href="\/test\/mark6\/ja\/oita360\/">大分360<\/a>/, 'renders Japanese section navigation label');
unlike($home, qr/href="\/test\/mark6\/ja\/articles\/">/, 'does not render reserved articles section navigation');
like($home, qr/<article class="article-summary">/, 'uses a full-width summary layout without an image');
unlike($home, qr/<article class="article-summary has-image">/, 'does not reserve an image column when no image exists');
unlike($home, qr/Older Article/, 'home article list honors mini_articles limit');
like($home, qr/href="\/test\/mark6\/ja\/oita360\/\?tag=%E3%83%8B%E3%83%A5%E3%83%BC%E3%82%B9"/, 'home tag URL uses localized tag and article node');

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
like($en_detail, qr/href="\/test\/mark6\/en\/oita360\/">Oita 360<\/a>/, 'renders English section navigation label');
like($en_detail, qr/<meta name="description" content="About Beppu Station">/, 'uses localized content when no matching language SEO description exists');
unlike($en_detail, qr/Japanese SEO description/, 'does not use a different language SEO description');
unlike($en_detail, qr/>Kiosk<\/h2>/, 'legacy Japanese Kiosk does not appear on English article');
unlike($en_detail, qr/Guide Book/, 'English article does not fall back to legacy Japanese Kiosk');
my $en_home = run_cgi('', '/en/');
unlike($en_home, qr/Home Guide/, 'English home does not fall back to legacy Japanese Kiosk');
like($en_home, qr/<div class="summary-taxonomy"><span>Oita Travel<\/span><span>Beppu<\/span><span>Spot<\/span><\/div>/, 'renders English localized article taxonomy');
my $nested_en_detail = run_cgi('', '/en/oita360/nested-tags/');
like($nested_en_detail, qr/Nested tags/, 'renders nested-tag compatibility article');
like($nested_en_detail, qr/>Nested EN<\/a>/, 'renders tags stored inside English language content');
like($nested_en_detail, qr/href="\/test\/mark6\/en\/oita360\/\?tag=Nested%20EN"/, 'renders localized URL for nested English tag');
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
like($en_home, qr/Welcome/, 'renders English home title');
like($en_home, qr/English home/, 'renders English home body');

my $home_data = read_json(File::Spec->catfile($root, 'dat', 'home.json'));
$home_data->{kiosk} = {
    enabled => JSON::PP::true,
    mode => 'auto',
    items => [],
};
write_json(File::Spec->catfile($root, 'dat', 'home.json'), $home_data);
my $auto_kiosk_home = run_cgi('', '/ja/');
like($auto_kiosk_home, qr/<span class="kiosk-label">Guide Book<\/span>/, 'auto home Kiosk reuses article Kiosk items');
like($auto_kiosk_home, qr/<span class="kiosk-label">Local Gift<\/span>/, 'auto home Kiosk renders another unique article Kiosk item');

my $localized_article = read_json(File::Spec->catfile($root, 'dat', 'articles', '1375451805.json'));
$localized_article->{kiosk} = {
    ja => $localized_article->{kiosk},
    en => {
        enabled => JSON::PP::true,
        items => [
            { label => 'Hotels near Beppu', type => 'url', url => 'https://example.com/hotels?city=beppu' },
            { label => 'Unsafe link', type => 'url', url => 'javascript:alert(1)' },
        ],
    },
};
write_json(File::Spec->catfile($root, 'dat', 'articles', '1375451805.json'), $localized_article);
my $localized_en_detail = run_cgi('', '/en/oita360/beppu-station/');
like($localized_en_detail, qr/>Kiosk<\/h2>/, 'renders localized English Kiosk');
like($localized_en_detail, qr/Hotels near Beppu/, 'renders English URL Kiosk label');
like($localized_en_detail, qr{href="https://example\.com/hotels\?city=beppu"}, 'uses entered external URL unchanged');
like($localized_en_detail, qr/<span class="kiosk-action">Open link<\/span>/, 'renders URL Kiosk action label');
unlike($localized_en_detail, qr/Unsafe link/, 'does not render a URL with an unsafe scheme');
unlike($localized_en_detail, qr/Guide Book/, 'localized English Kiosk does not include Japanese items');

$home_data->{kiosk} = {
    ja => $home_data->{kiosk},
    en => { enabled => JSON::PP::true, mode => 'auto', items => [] },
};
write_json(File::Spec->catfile($root, 'dat', 'home.json'), $home_data);
my $auto_en_home = run_cgi('', '/en/');
like($auto_en_home, qr/Hotels near Beppu/, 'English auto home Kiosk reuses English article Kiosk items');
unlike($auto_en_home, qr/Guide Book/, 'English auto home Kiosk does not reuse Japanese article Kiosk items');

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
like($list, qr/タグ: News/, 'renders tag page with localized heading label');
ok(-e File::Spec->catfile($root, 'dat', 'logs', 'access.jsonl'), 'writes privacy-minimized access log');
like($list, qr/href="\/test\/mark6\/ja\/oita360\/\?tag=%E3%83%8B%E3%83%A5%E3%83%BC%E3%82%B9"/, 'renders localized tag URL from site base');
like($list, qr/別府駅/, 'renders filtered article');
unlike($list, qr/Older Article/, 'tag page honors articles_per_page');
my $list_page_2 = run_cgi('order=article&tag=News&page=2');
like($list_page_2, qr/Older Article/, 'tag page renders page 2');

my $ja_tag_list = run_cgi('tag=%E3%83%8B%E3%83%A5%E3%83%BC%E3%82%B9', '/ja/oita360/');
like($ja_tag_list, qr/タグ: ニュース/, 'renders localized Japanese tag page heading');
like($ja_tag_list, qr/別府駅/, 'localized Japanese tag filters articles');

my $disabled_kiosk = run_cgi('', '/ja/oita360/older-post/');
unlike($disabled_kiosk, qr/Hidden Item/, 'does not render disabled kiosk items');

write_json(File::Spec->catfile($root, 'dat', 'articles', 'about-page.json'), {
    id => 'about-page',
    type => 'page',
    status => 'published',
    default_lang => 'ja',
    slug => 'about',
    langs => {
        ja => { title => 'このサイトについて', description => '', body => '<p>固定ページ本文</p>' },
        en => { title => 'About this site', description => '', body => '<p>English page body</p>' },
    },
    created_at => '2026-09-09T00:00:00Z',
});

my $page_ja = run_cgi('', '/about/');
like($page_ja, qr/このサイトについて/, 'renders default-language fixed page without language prefix');
like($page_ja, qr/固定ページ本文/, 'renders fixed page body');
like($page_ja, qr/href="\/test\/mark6\/en\/about\/"/, 'fixed page language switch uses page URL');
unlike($page_ja, qr/class="kiosk"/, 'fixed page does not render article Kiosk');

my $page_en = run_cgi('', '/en/about/');
like($page_en, qr/About this site/, 'renders English fixed page');
like($page_en, qr/English page body/, 'renders English fixed page body');

my $article_list_without_page = run_cgi('', '/ja/oita360/');
unlike($article_list_without_page, qr/このサイトについて/, 'fixed page is excluded from article list');

my $enhanced_config = read_json(File::Spec->catfile($root, 'dat', 'config.json'));
$enhanced_config->{navigation} = {
    header => {
        ja => [
            { label => 'ホームへ', url => '/', enabled => JSON::PP::true },
            { label => 'このサイトについて', url => '/about/', enabled => JSON::PP::true },
            { label => '非表示', url => '/hidden/', enabled => JSON::PP::false },
        ],
        en => [ { label => 'About', url => '/en/about/', enabled => JSON::PP::true } ],
    },
    footer => {
        ja => [ { label => 'プライバシー', url => '/privacy/', enabled => JSON::PP::true } ],
        en => [ { label => 'Privacy', url => '/en/privacy/', enabled => JSON::PP::true } ],
    },
};
$enhanced_config->{free_space} = {
    home_bottom => {
        ja => { enabled => JSON::PP::true, html => '<aside>HOME FREE JA</aside>' },
        en => { enabled => JSON::PP::false, html => '<aside>HOME FREE EN</aside>' },
    },
    article_end => {
        ja => { enabled => JSON::PP::true, html => '<aside>ARTICLE END JA</aside>' },
    },
    after_kiosk => {
        ja => { enabled => JSON::PP::true, html => '<aside>AFTER KIOSK JA</aside>' },
    },
};
write_json(File::Spec->catfile($root, 'dat', 'config.json'), $enhanced_config);

my $configured_home = run_cgi('', '/ja/');
like($configured_home, qr/>ホーム<\/a>/, 'configured navigation keeps automatic home link by default');
like($configured_home, qr/href="\/test\/mark6\/ja\/">ホームへ<\/a>/, 'configured root navigation uses localized home URL and site base');
like($configured_home, qr/href="\/test\/mark6\/about\/">このサイトについて<\/a>/, 'configured fixed-page navigation uses site base');
unlike($configured_home, qr/>非表示<\/a>/, 'disabled navigation item is hidden');
like($configured_home, qr/<nav class="footer-nav"><a href="\/test\/mark6\/privacy\/">プライバシー<\/a><\/nav>/, 'renders configured footer navigation');
like($configured_home, qr/<section class="free-space free-space-home-bottom"><aside>HOME FREE JA<\/aside><\/section>/, 'renders Japanese home free space');

my $configured_en_home = run_cgi('', '/en/');
like($configured_en_home, qr/href="\/test\/mark6\/en\/about\/">About<\/a>/, 'renders English navigation independently');
unlike($configured_en_home, qr/HOME FREE JA/, 'English free space does not fall back to Japanese');
unlike($configured_en_home, qr/HOME FREE EN/, 'disabled English free space is hidden');

$enhanced_config->{navigation}{header}{system} = {
    home => JSON::PP::false,
    articles => JSON::PP::false,
    sections => JSON::PP::false,
};
write_json(File::Spec->catfile($root, 'dat', 'config.json'), $enhanced_config);
my $manual_only_home = run_cgi('', '/ja/');
unlike($manual_only_home, qr/>ホーム<\/a>/, 'automatic home link can be disabled');
unlike($manual_only_home, qr/>記事<\/a>/, 'automatic articles link can be disabled');
like($manual_only_home, qr/>ホームへ<\/a>/, 'manual navigation remains after disabling automatic links');

my $configured_detail = run_cgi('', '/ja/oita360/beppu-station/');
like($configured_detail, qr/ARTICLE END JA/, 'renders article_end free space');
like($configured_detail, qr/AFTER KIOSK JA/, 'renders after_kiosk free space after an enabled Kiosk');
like($configured_detail, qr/ARTICLE END JA.*class="kiosk".*AFTER KIOSK JA/s, 'free-space slots keep article and Kiosk order');

my $enhanced_sitemap = run_cgi('', '/sitemap.xml');
like($enhanced_sitemap, qr/http:\/\/localhost\/test\/mark6\/about\//, 'sitemap includes default-language fixed page');
like($enhanced_sitemap, qr/http:\/\/localhost\/test\/mark6\/en\/about\//, 'sitemap includes English fixed page');

# Even an accidentally published memory remains invisible until review.
write_json(File::Spec->catfile($root, 'dat', 'articles', 'private-memory.json'), {
    id => 'private-memory', slug => 'private-memory', node => 'sati-memory',
    title => 'PRIVATE-SENTINEL', intro => 'PRIVATE-SENTINEL', body => 'PRIVATE-SENTINEL',
    status => 'published', memory => { source => 'sati' }, review => { state => 'pending' },
});
for my $path ('/ja/', '/ja/sati-memory/', '/ja/sati-memory/private-memory/', '/sitemap.xml', '/rss.xml', '/api/articles') {
    unlike(run_cgi('', $path), qr/PRIVATE-SENTINEL|private-memory/, "unapproved memory hidden: $path");
}
unlike(run_cgi('order=focus&tar=private-memory', ''), qr/PRIVATE-SENTINEL/, 'legacy direct ID route hides memory');
unlike(run_cgi('order=article&tag=private-tag', ''), qr/PRIVATE-SENTINEL<\//, 'filtered list hides memory');
remove_tree($root);
done_testing;

sub run_cgi {
    my ($query, $path_info, $request_uri, $accept_language, $cookie) = @_;
    local $ENV{QUERY_STRING} = $query;
    local $ENV{PATH_INFO} = $path_info || '';
    local $ENV{REQUEST_URI} = $request_uri || '';
    local $ENV{HTTP_ACCEPT_LANGUAGE} = $accept_language || '';
    local $ENV{HTTP_COOKIE} = $cookie || '';
    local $ENV{HTTP_USER_AGENT} = 'MARK6 test browser';
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

sub read_json {
    my ($path) = @_;
    open my $fh, '<:encoding(UTF-8)', $path or die "Cannot read $path: $!";
    local $/;
    my $json = <$fh>;
    close $fh;
    return JSON::PP->new->utf8(0)->decode($json);
}
