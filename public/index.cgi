#!/usr/bin/env perl

use strict;
use warnings;
use utf8;
use FindBin;
use Cwd qw(abs_path getcwd);
use Encode qw(decode encode);
use File::Basename qw(dirname);

BEGIN {
    my @lib_candidates = (
        "$FindBin::Bin/../lib",
        './lib',
        '../lib',
    );

    for my $lib (@lib_candidates) {
        if (-d $lib) {
            unshift @INC, $lib;
            last;
        }
    }
}

use Mark6::DataStore;
use Mark6::Article;
use Mark6::Root;

my $ROOT = $ENV{MARK6_ROOT} || Mark6::Root::default_root(findbin => $FindBin::Bin, script => $0, marker => 'dat/config.json');
my $store = Mark6::DataStore->new(root => $ROOT);
my %in = parse_query();

my $config = $store->read_json('dat', 'config.json') || {};
my $home   = $store->read_json('dat', 'home.json') || {};
my @supported_langs = Mark6::Article::supported_langs($config);
my $site_base = site_base($config);
my $asset_base = asset_base($config, $site_base);
my $request_path = request_path();
my $route = parse_route($request_path, \@supported_langs, $config);
my $current_lang = current_lang($config, \@supported_langs, $route);
my $order  = $in{order} || 'index';

if ($request_path eq 'robots.txt') {
    print encode('UTF-8', render_robots());
    exit;
}

if ($request_path eq 'sitemap.xml') {
    print encode('UTF-8', render_sitemap());
    exit;
}

if (should_redirect_root($request_path, $route)) {
    my $initial_lang = initial_lang(\@supported_langs);
    redirect_to(lang_url($initial_lang));
    exit;
}

my $site_title = value_at($config, 'site', 'title') || 'MARK6';
my $content;
my $page_title = $site_title;
my $page_description = '';
my $canonical_url = '';
my $access_article;

if ($route->{type} eq 'article') {
    my $article = find_article_by_slug($route->{node}, $route->{slug});
    if ($article) {
        $page_title = Mark6::Article::title_for($article, $current_lang, $config) . " - $site_title";
        $page_description = article_meta_description($article);
        $canonical_url = site_absolute_url(article_url($article, $current_lang));
        $access_article = $article;
        $content = render_article_detail($article);
    }
    else {
        $content = render_not_found();
    }
}
elsif ($route->{type} eq 'node') {
    my @articles = grep { Mark6::Article::node_for($_, $config) eq $route->{node} } load_articles();
    $content = render_article_list(\@articles, undef);
}
elsif ($order eq 'focus') {
    my $article = find_article($in{tar} || '');
    if ($article) {
        $page_title = Mark6::Article::title_for($article, $current_lang, $config) . " - $site_title";
        $page_description = article_meta_description($article);
        $canonical_url = site_absolute_url(article_url($article, $current_lang));
        $access_article = $article;
        $content = render_article_detail($article);
    }
    else {
        $content = render_not_found();
    }
}
elsif ($order eq 'article') {
    my @articles = load_articles();
    @articles = filter_by_tag(\@articles, $in{tag}) if defined $in{tag} && $in{tag} ne '';
    $content = render_article_list(\@articles, $in{tag});
}
else {
    my @articles = load_articles();
    $content = render_home($home, \@articles);
}

$canonical_url ||= canonical_url($route);
log_access($route, $access_article);
print encode('UTF-8', render_page($page_title, $site_title, $content, $page_description, $canonical_url, $access_article));

sub parse_query {
    my $query = $ENV{QUERY_STRING} || '';
    my %params;

    for my $pair (split /[&;]/, $query) {
        next if $pair eq '';
        my ($key, $value) = split /=/, $pair, 2;
        $key = url_decode($key || '');
        $value = url_decode($value || '');
        $params{$key} = $value;
    }

    return %params;
}

sub request_path {
    my $path = $ENV{PATH_INFO} || '';
    return normalize_path($in{path}) if $path eq '' && exists $in{path};
    if ($path eq '') {
        $path = $ENV{REQUEST_URI} || '';
        $path =~ s/\?.*\z//;
    }

    return normalize_path($path);
}

sub normalize_path {
    my ($path) = @_;
    $path = '' unless defined $path;
    $path =~ s{\\}{/}g;
    $path =~ s{(?:^|/)public/index\.cgi(?:/|$)}{/}i;
    $path =~ s{/+}{/}g;
    $path =~ s{\A/+}{};
    $path =~ s{/+\z}{};
    my $base = $site_base || '';
    $base =~ s{\Ahttps?://[^/]+}{}i;
    $base =~ s{\A/+}{};
    $base =~ s{/+\z}{};
    $path =~ s{\A\Q$base\E/?}{} if $base ne '';
    return $path;
}

sub parse_route {
    my ($path, $langs, $config) = @_;
    my %supported = map { $_ => 1 } @{$langs};
    my $default = $config->{site}{default_lang} || $config->{site}{language} || $langs->[0] || 'ja';
    my @parts = grep { $_ ne '' } split m{/+}, $path || '';
    @parts = map { url_decode($_) } @parts;

    return { type => 'index', lang => $default } unless @parts;

    my $lang = $default;
    if ($supported{$parts[0]}) {
        $lang = shift @parts;
    }
    elsif (@parts >= 2 && $parts[0] =~ /\A[a-z][a-z0-9_-]*\z/i) {
        shift @parts;
    }

    return { type => 'index', lang => $lang } unless @parts;
    return { type => 'node', lang => $lang, node => $parts[0] } if @parts == 1;
    return { type => 'article', lang => $lang, node => $parts[0], slug => $parts[1] };
}

sub current_lang {
    my ($config, $langs, $route) = @_;
    my %supported = map { $_ => 1 } @{$langs};
    my $path_lang = $route->{lang} || '';
    my $query_lang = $in{lang} || '';
    my $default = $config->{site}{default_lang} || $config->{site}{language} || $langs->[0] || 'ja';
    return $path_lang if $supported{$path_lang};
    return $query_lang if $supported{$query_lang};
    return $supported{$default} ? $default : $langs->[0] || 'ja';
}

sub should_redirect_root {
    my ($path, $route) = @_;
    return 0 if ($ENV{REQUEST_METHOD} || 'GET') ne 'GET';
    return 0 if $order ne 'index';
    return 0 if defined $in{tag} || defined $in{tar};
    return ($path || '') eq '' && ($route->{type} || '') eq 'index';
}

sub initial_lang {
    my ($langs) = @_;
    my %supported = map { $_ => 1 } @{$langs};
    my %cookies = cookies();
    return $cookies{mark6_lang} if $supported{$cookies{mark6_lang} || ''};

    my $accept = lc($ENV{HTTP_ACCEPT_LANGUAGE} || '');
    return 'ja' if $accept =~ /\A\s*ja(?:-|,|;|\z)/;
    return 'ja' if $accept =~ /\A\s*ja-jp(?:,|;|\z)/;
    return $supported{en} ? 'en' : ($langs->[0] || 'ja');
}

sub cookies {
    my %cookies;
    for my $pair (split /;\s*/, $ENV{HTTP_COOKIE} || '') {
        my ($key, $value) = split /=/, $pair, 2;
        next unless defined $key && $key ne '';
        $cookies{$key} = url_decode($value || '');
    }
    return %cookies;
}

sub redirect_to {
    my ($location) = @_;
    print encode('UTF-8', <<"HTTP");
Status: 302 Found
Location: $location

HTTP
}

sub url_decode {
    my ($value) = @_;
    $value =~ tr/+/ /;
    $value =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
    return decode('UTF-8', $value);
}

sub load_articles {
    my $dir = "$ROOT/dat/articles";
    return () unless -d $dir;

    opendir my $dh, $dir or die "Cannot open $dir: $!";
    my @files = grep { /\.json\z/ } readdir $dh;
    closedir $dh;

    my @articles;
    for my $file (@files) {
        my $article = $store->read_json('dat', 'articles', $file);
        next unless $article && ($article->{status} || '') eq 'published';
        Mark6::Article::normalize($article, $config);
        push @articles, $article;
    }

    return sort { ($b->{id} || 0) <=> ($a->{id} || 0) } @articles;
}

sub find_article {
    my ($id) = @_;
    return undef unless $id =~ /\A[0-9A-Za-z_-]+\z/;

    my $article = $store->read_json('dat', 'articles', "$id.json");
    return undef unless $article && ($article->{status} || '') eq 'published';
    Mark6::Article::normalize($article, $config);
    return $article;
}

sub find_article_by_slug {
    my ($node, $slug) = @_;
    return undef unless safe_segment($node) && safe_segment($slug);

    for my $article (load_articles()) {
        next unless Mark6::Article::node_for($article, $config) eq $node;
        next unless Mark6::Article::slug_for($article) eq $slug;
        return $article;
    }

    return undef;
}

sub filter_by_tag {
    my ($articles, $tag) = @_;
    return grep {
        my %tags = map { $_ => 1 } @{$_->{tags} || []};
        $tags{$tag};
    } @{$articles};
}

sub render_home {
    my ($home, $articles) = @_;
    my $title = escape_html($home->{title} || 'Home');
    my $body = trusted_html($home->{body} || '');
    my $article_list = $home->{show_articles} ? render_article_list($articles, undef, 5) : '';

    return <<"HTML";
<section class="home">
  <h1>$title</h1>
  <div class="body">$body</div>
</section>
$article_list
HTML
}

sub render_article_list {
    my ($articles, $tag, $limit) = @_;
    my @items = @{$articles};
    @items = @items[0 .. $limit - 1] if $limit && @items > $limit;

    my $heading = defined $tag && $tag ne ''
        ? 'Tag: ' . escape_html($tag)
        : 'Articles';

    my $body = @items
        ? join("\n", map { render_article_summary($_) } @items)
        : '<p class="empty">No articles yet.</p>';

    return <<"HTML";
<section class="article-list">
  <h2>$heading</h2>
  $body
</section>
HTML
}

sub render_article_summary {
    my ($article) = @_;
    my $title = escape_html(Mark6::Article::title_for($article, $current_lang, $config));
    my $date = escape_html(format_date($article->{created_at} || ''));
    my $intro = trusted_html(Mark6::Article::description_for($article, $current_lang, $config));
    my $tags = render_tags($article->{tags} || []);
    my $image = render_image($article, 'summary-image');
    my $image_class = $image ne '' ? ' has-image' : '';
    my $href = escape_attr(article_url($article, $current_lang));

    return <<"HTML";
<article class="article-summary$image_class">
  $image
  <div class="summary-main">
    <div class="meta">$date</div>
    <h3><a href="$href">$title</a></h3>
    <div class="intro">$intro</div>
    $tags
  </div>
</article>
HTML
}

sub render_article_detail {
    my ($article) = @_;
    my $title = escape_html(Mark6::Article::title_for($article, $current_lang, $config));
    my $date = escape_html(format_date($article->{created_at} || ''));
    my $intro = trusted_html(Mark6::Article::description_for($article, $current_lang, $config));
    my $body = trusted_html(Mark6::Article::body_for($article, $current_lang, $config));
    my $tags = render_tags($article->{tags} || []);
    my $image = render_image($article, 'detail-image');
    my $lang_links = render_language_links($article);

    $body = $intro if $body eq '';

    return <<"HTML";
<article class="article-detail">
  <a class="back-link" href="@{[escape_attr(article_list_url())]}">Articles</a>
  <div class="meta">$date</div>
  $lang_links
  <h1>$title</h1>
  $image
  <div class="body">$body</div>
  $tags
</article>
HTML
}

sub render_tags {
    my ($tags) = @_;
    return '' unless @{$tags};

    my $links = join ' ', map {
        my $tag = escape_html($_);
        my $url = escape_attr(url_encode($_));
        my $href = escape_attr(article_list_url("tag=$url"));
        qq|<a href="$href">$tag</a>|;
    } @{$tags};

    return qq|<nav class="tags">$links</nav>|;
}

sub render_image {
    my ($article, $class) = @_;
    my $image = $article->{image} || '';
    return '' unless safe_image_path($image);

    my $src = escape_attr(image_src($image));
    my $alt = escape_attr(Mark6::Article::title_for($article, $current_lang, $config));
    return qq|<img class="$class" src="$src" alt="$alt">|;
}

sub render_language_links {
    my ($article) = @_;
    my $links = join ' ', map {
        my $lang = $_;
        my $href = $article
            ? article_url($article, $lang)
            : lang_url($lang);
        $href = escape_attr($href);
        my $class = $lang eq $current_lang ? ' class="active"' : '';
        qq|<a$class href="$href">$lang</a>|;
    } @supported_langs;

    return qq|<nav class="language-switch">$links</nav>|;
}

sub image_src {
    my ($image) = @_;
    return $image =~ m{\Aimg/} ? site_url($image) : site_url("img/$image");
}

sub safe_image_path {
    my ($value) = @_;
    return 0 unless defined $value && $value ne '';
    return 0 if $value =~ /\.\./;
    return $value =~ /\A[0-9A-Za-z_.\/-]+\z/ ? 1 : 0;
}

sub safe_segment {
    my ($value) = @_;
    return defined $value && $value =~ /\A[0-9A-Za-z_-]+\z/ ? 1 : 0;
}

sub render_not_found {
    my $home = escape_attr(lang_url($current_lang));
    return <<"HTML";
<section class="not-found">
  <h1>Article not found</h1>
  <p>The requested article is not available.</p>
  <p><a href="$home">Back to home</a></p>
</section>
HTML
}

sub render_robots {
    my $sitemap = site_absolute_url(site_url('sitemap.xml'));
    return "Content-Type: text/plain; charset=UTF-8\n\nUser-agent: *\nAllow: /\nSitemap: $sitemap\n";
}

sub render_sitemap {
    my @urls;
    for my $lang (@supported_langs) {
        push @urls, { loc => site_absolute_url(lang_url($lang)), lastmod => '' };
    }
    for my $article (load_articles()) {
        my $lastmod = format_date($article->{updated_at} || $article->{created_at} || '');
        for my $lang (@supported_langs) {
            push @urls, {
                loc => site_absolute_url(article_url($article, $lang)),
                lastmod => $lastmod,
            };
        }
    }

    my $items = join '', map {
        my $lastmod = $_->{lastmod} ne '' ? '<lastmod>' . xml_escape($_->{lastmod}) . '</lastmod>' : '';
        '<url><loc>' . xml_escape($_->{loc}) . '</loc>' . $lastmod . '</url>' . "\n";
    } @urls;
    return "Content-Type: application/xml; charset=UTF-8\n\n<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n$items</urlset>\n";
}

sub canonical_url {
    my ($route) = @_;
    if (($route->{type} || '') eq 'node') {
        return site_absolute_url(site_url("$current_lang/$route->{node}/"));
    }
    if ($order eq 'article' && defined $in{tag} && $in{tag} ne '') {
        return site_absolute_url(article_list_url('tag=' . url_encode($in{tag})));
    }
    return site_absolute_url(lang_url($current_lang));
}

sub site_absolute_url {
    my ($url) = @_;
    return $url if $url =~ m{\Ahttps?://}i;
    my $host = $ENV{HTTP_HOST} || 'localhost';
    my $scheme = ($ENV{HTTPS} || '') =~ /\A(?:on|1)\z/i ? 'https' : 'http';
    $url = "/$url" unless $url =~ m{\A/};
    return "$scheme://$host$url";
}

sub log_access {
    my ($route, $article) = @_;
    return if $ENV{MARK6_DISABLE_ACCESS_LOG};

    my @t = gmtime(time);
    my $iso = sprintf('%04d-%02d-%02dT%02d:%02d:%02dZ',
        $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0]);
    my $event = {
        kind          => 'page',
        at            => $iso,
        day           => substr($iso, 0, 10),
        lang          => $current_lang,
        route          => $route->{type} || 'index',
        article_id    => $article ? ($article->{id} || '') : '',
        article_title => $article ? Mark6::Article::title_for($article, $current_lang, $config) : '',
    };
    eval { $store->append_jsonl($event, 'dat', 'logs', 'access.jsonl'); 1 };
}

sub article_meta_description {
    my ($article) = @_;
    my $seo = (($article->{ai} || {})->{seo} || {});
    my $seo_lang = $seo->{lang} || Mark6::Article::default_lang($article, $config);
    my $description = $seo_lang eq $current_lang ? ($seo->{seo_description} || '') : '';
    $description = Mark6::Article::description_for($article, $current_lang, $config) if $description eq '';
    $description = Mark6::Article::title_for($article, $current_lang, $config) if $description eq '';
    return plain_text($description);
}

sub render_page {
    my ($page_title, $site_title, $content, $page_description, $canonical_url, $article) = @_;
    my $safe_page_title = escape_html($page_title);
    my $safe_site_title = escape_html($site_title);
    my $language_links = render_language_links();
    my $home_href = escape_attr(lang_url($current_lang));
    my $articles_href = escape_attr(article_list_url());
    my ($home_label, $articles_label) = public_nav_labels();
    $home_label = escape_html($home_label);
    $articles_label = escape_html($articles_label);
    my $css_href = escape_attr(asset_url('css/mark6.css') . '?v=2');
    my $favicon_href = escape_attr(asset_url('img/mark6-icon.svg') . '?v=2');
    my $footer_logo = escape_attr(asset_url('img/mark6-logo-light.svg') . '?v=2');
    my $lang_cookie = lang_cookie_header();
    my $safe_page_description = escape_attr($page_description || '');
    my $safe_canonical_url = escape_attr($canonical_url || '');
    my $description_meta = $page_description ne ''
        ? qq|  <meta name="description" content="$safe_page_description">\n|
        : '';
    my $canonical_meta = $canonical_url ne '' ? qq|  <link rel="canonical" href="$safe_canonical_url">\n| : '';
    my $og_type = $article ? 'article' : 'website';
    my $og_meta = qq|  <meta property="og:type" content="$og_type">\n| .
        qq|  <meta property="og:title" content="@{[escape_attr($page_title)]}">\n| .
        ($page_description ne '' ? qq|  <meta property="og:description" content="$safe_page_description">\n| : '') .
        ($canonical_url ne '' ? qq|  <meta property="og:url" content="$safe_canonical_url">\n| : '');
    if ($article && safe_image_path($article->{image} || '')) {
        my $image_url = escape_attr(site_absolute_url(image_src($article->{image})));
        $og_meta .= qq|  <meta property="og:image" content="$image_url">\n|;
    }

    return <<"HTML";
Content-Type: text/html; charset=UTF-8
$lang_cookie

<!doctype html>
<html lang="$current_lang">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  $description_meta
  $canonical_meta
  $og_meta
  <title>$safe_page_title</title>
  <link rel="icon" href="$favicon_href" type="image/svg+xml">
  <link rel="stylesheet" href="$css_href">
</head>
<body>
  <header class="site-header">
    <a class="brand" href="$home_href">$safe_site_title</a>
    <nav class="site-nav">
      <a href="$home_href">$home_label</a>
      <a href="$articles_href">$articles_label</a>
    </nav>
    $language_links
  </header>
  <main class="site-main">
    $content
  </main>
  <footer class="site-footer">
    <img src="$footer_logo" alt="MARK6">
    <span>Powered by MARK6</span>
  </footer>
</body>
</html>
HTML
}

sub public_nav_labels {
    return $current_lang eq 'ja' ? ('ホーム', '記事') : ('Home', 'Articles');
}

sub trusted_html {
    my ($html) = @_;
    return $html;
}

sub plain_text {
    my ($value) = @_;
    $value = '' unless defined $value;
    $value =~ s/<[^>]+>/ /g;
    $value =~ s/&nbsp;/ /g;
    $value =~ s/&amp;/&/g;
    $value =~ s/&lt;/</g;
    $value =~ s/&gt;/>/g;
    $value =~ s/\s+/ /g;
    $value =~ s/^\s+|\s+$//g;
    return $value;
}

sub xml_escape {
    my ($value) = @_;
    $value = '' unless defined $value;
    $value =~ s/&/&amp;/g;
    $value =~ s/</&lt;/g;
    $value =~ s/>/&gt;/g;
    $value =~ s/"/&quot;/g;
    $value =~ s/'/&apos;/g;
    return $value;
}

sub lang_cookie_header {
    return '' unless grep { $_ eq $current_lang } @supported_langs;
    my $path = cookie_path();
    return "Set-Cookie: mark6_lang=$current_lang; Path=$path; Max-Age=31536000; SameSite=Lax\n";
}

sub cookie_path {
    my $path = $site_base eq '' ? '/' : "$site_base/";
    $path =~ s{\Ahttps?://[^/]+}{}i;
    $path =~ s{/+}{/}g;
    return $path;
}

sub site_base {
    my ($config) = @_;
    my $base = value_at($config, 'site', 'base_url') || '';
    if ($base eq '') {
        $base = $ENV{SCRIPT_NAME} || '';
        $base =~ s{/public/index\.cgi\z}{}i;
        $base =~ s{/index\.cgi\z}{}i;
    }

    $base =~ s{\\}{/}g;
    $base =~ s{/+\z}{};
    $base = '' if $base eq '/';
    return $base;
}

sub asset_base {
    my ($config, $site_base) = @_;
    my $base = value_at($config, 'site', 'asset_base') || '';
    return clean_url_base($base) if $base ne '';
    return site_url('assets');
}

sub clean_url_base {
    my ($base) = @_;
    $base =~ s{\\}{/}g;
    $base =~ s{/+\z}{};
    return $base;
}

sub site_url {
    my ($path) = @_;
    $path ||= '';
    $path =~ s{\A/+}{};
    return $site_base eq '' ? "/$path" : "$site_base/$path";
}

sub asset_url {
    my ($path) = @_;
    $path ||= '';
    $path =~ s{\A/+}{};
    return "$asset_base/$path";
}

sub lang_url {
    my ($lang) = @_;
    return site_url("$lang/");
}

sub article_url {
    my ($article, $lang) = @_;
    my $path = Mark6::Article::public_path($article, $lang, $config);
    return site_url($path);
}

sub article_list_url {
    my ($query) = @_;
    my $url = lang_url($current_lang);
    return defined $query && $query ne '' ? "$url?$query" : $url;
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

sub escape_attr {
    return escape_html(@_);
}

sub url_encode {
    my ($value) = @_;
    $value = encode('UTF-8', $value);
    $value =~ s/([^A-Za-z0-9_.~-])/sprintf('%%%02X', ord($1))/eg;
    return $value;
}

sub format_date {
    my ($iso) = @_;
    return '' unless $iso =~ /\A(\d{4})-(\d{2})-(\d{2})/;
    return "$1-$2-$3";
}

sub value_at {
    my ($hash, @path) = @_;
    my $current = $hash;
    for my $key (@path) {
        return undef unless ref($current) eq 'HASH';
        $current = $current->{$key};
    }
    return $current;
}

sub default_root {
    my $script = abs_path($0);
    my @candidates = (
        getcwd(),
        dirname(getcwd()),
        defined($script) && $script ne '' ? dirname(dirname($script)) : (),
        "$FindBin::Bin/..",
    );

    for my $candidate (@candidates) {
        next unless defined $candidate && $candidate ne '';
        return $candidate if -e "$candidate/dat/config.json";
    }

    return "$FindBin::Bin/..";
}
