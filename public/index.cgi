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
use Mark6::Kiosk qw(config_for_lang item_type valid_url);
use Mark6::Root;
use Mark6::TrafficFilter;

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
my $default_article_node_cache;

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
    my $page = find_page_by_slug($route->{node});
    if ($page) {
        $route = { %{$route}, type => 'page', slug => $route->{node} };
        $page_title = Mark6::Article::title_for($page, $current_lang, $config) . " - $site_title";
        $page_description = article_meta_description($page);
        $canonical_url = site_absolute_url(article_url($page, $current_lang));
        $access_article = $page;
        $content = render_fixed_page($page);
    }
    else {
        my @articles = grep { Mark6::Article::node_for($_, $config) eq $route->{node} } load_articles();
        @articles = filter_by_tag(\@articles, $in{tag}) if defined $in{tag} && $in{tag} ne '';
        $content = render_article_list(\@articles, $in{tag}, node => $route->{node});
    }
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
    my @articles = load_articles(limit => home_article_limit());
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
    my (%args) = @_;
    my $dir = "$ROOT/dat/articles";
    return () unless -d $dir;

    opendir my $dh, $dir or die "Cannot open $dir: $!";
    my @files = grep { /\.json\z/ } readdir $dh;
    closedir $dh;

    my $limit = bounded_number($args{limit}, 0, 0, 100);

    my @articles;
    for my $file (@files) {
        my $article = $store->read_json('dat', 'articles', $file);
        next unless $article && ($article->{status} || '') eq 'published';
        next unless Mark6::Article::content_type($article) eq 'article';
        Mark6::Article::normalize($article, $config);
        push @articles, $article;
    }

    @articles = sort article_sort @articles;
    @articles = @articles[0 .. $limit - 1] if $limit && @articles > $limit;
    return @articles;
}

sub find_article {
    my ($id) = @_;
    return undef unless $id =~ /\A[0-9A-Za-z_-]+\z/;

    my $article = $store->read_json('dat', 'articles', "$id.json");
    return undef unless $article && ($article->{status} || '') eq 'published';
    return undef unless Mark6::Article::content_type($article) eq 'article';
    Mark6::Article::normalize($article, $config);
    return $article;
}

sub load_pages {
    my $dir = "$ROOT/dat/articles";
    return () unless -d $dir;
    opendir my $dh, $dir or die "Cannot open $dir: $!";
    my @files = grep { /\.json\z/ } readdir $dh;
    closedir $dh;

    my @pages;
    for my $file (@files) {
        my $page = $store->read_json('dat', 'articles', $file);
        next unless $page && ($page->{status} || '') eq 'published';
        next unless Mark6::Article::content_type($page) eq 'page';
        Mark6::Article::normalize($page, $config);
        push @pages, $page;
    }
    return sort article_sort @pages;
}

sub find_page_by_slug {
    my ($slug) = @_;
    return undef unless safe_segment($slug);
    for my $page (load_pages()) {
        return $page if Mark6::Article::slug_for($page) eq $slug;
    }
    return undef;
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
        article_has_tag($_, $tag);
    } @{$articles};
}

sub render_home {
    my ($home, $articles) = @_;
    my $localized = localized_home($home);
    my $title = escape_html($localized->{title} || 'Home');
    my $body = trusted_html($localized->{body} || '');
    my $article_list = $home->{show_articles} ? render_article_list($articles, undef, home => 1) : '';
    my $kiosk = render_home_kiosk($home, $articles);
    my $free_space = render_free_space('home_bottom');

    return <<"HTML";
<section class="home">
  <h1>$title</h1>
  <div class="body">$body</div>
</section>
$article_list
$kiosk
$free_space
HTML
}

sub render_article_list {
    my ($articles, $tag, %args) = @_;
    my @items = @{$articles};
    my $pagination = '';

    unless ($args{home}) {
        my $page = current_page();
        my $per_page = article_page_limit();
        my $total = scalar @items;
        if ($per_page && $total > $per_page) {
            my $last_page = int(($total + $per_page - 1) / $per_page);
            $page = $last_page if $page > $last_page;
            my $offset = ($page - 1) * $per_page;
            @items = @items[$offset .. ($offset + $per_page - 1 > $#items ? $#items : $offset + $per_page - 1)];
            $pagination = render_pagination($page, $last_page, $tag, $args{node});
        }
    }

    my ($home_label, $articles_label, $tag_label) = public_nav_labels();
    my $heading = defined $tag && $tag ne ''
        ? $tag_label . ': ' . escape_html($tag)
        : $articles_label;

    my $body = @items
        ? join("\n", map { render_article_summary($_) } @items)
        : '<p class="empty">No articles yet.</p>';

    return <<"HTML";
<section class="article-list">
  <h2>$heading</h2>
  $body
  $pagination
</section>
HTML
}

sub localized_home {
    my ($home) = @_;
    my $default = $config->{site}{default_lang} || $config->{site}{language} || 'ja';
    my $langs = ref($home->{langs}) eq 'HASH' ? $home->{langs} : {};
    my $entry = ref($langs->{$current_lang}) eq 'HASH' ? $langs->{$current_lang} : {};
    my $fallback = ref($langs->{$default}) eq 'HASH' ? $langs->{$default} : {};

    return {
        title => first_text($entry->{title}, $fallback->{title}, $home->{title}, 'Home'),
        body  => first_text($entry->{body}, $fallback->{body}, $home->{body}, ''),
    };
}

sub render_article_summary {
    my ($article) = @_;
    my $title = escape_html(Mark6::Article::title_for($article, $current_lang, $config));
    my $date = escape_html(format_date($article->{created_at} || ''));
    my $intro = trusted_html(Mark6::Article::description_for($article, $current_lang, $config));
    my $tags = render_tags(article_tags_for_lang($article, $current_lang), $article);
    my $image = render_image($article, 'summary-image');
    my $image_class = $image ne '' ? ' has-image' : '';
    my $href = escape_attr(article_url($article, $current_lang));
    my $taxonomy = render_article_taxonomy($article);

    return <<"HTML";
<article class="article-summary$image_class">
  $image
  <div class="summary-main">
    <div class="meta">$date</div>
    <h3><a href="$href">$title</a></h3>
    $taxonomy
    <div class="intro">$intro</div>
    $tags
  </div>
</article>
HTML
}

sub render_article_taxonomy {
    my ($article) = @_;
    my $meta = ref($article->{article}) eq 'HASH' ? $article->{article} : {};
    my $location = ref($meta->{location}) eq 'HASH' ? $meta->{location} : {};
    my @parts;

    push @parts, localized_taxonomy_value($meta, 'series');
    push @parts, localized_taxonomy_value($location, 'city');
    push @parts, localized_taxonomy_value($meta, 'type');
    @parts = grep { defined && $_ ne '' } @parts;

    return '' unless @parts;
    my $items = join '', map { '<span>' . escape_html($_) . '</span>' } @parts;
    return qq|<div class="summary-taxonomy">$items</div>|;
}

sub localized_taxonomy_value {
    my ($source, $field) = @_;
    return '' unless ref($source) eq 'HASH';

    my $langs_key = $field . '_langs';
    my $labels_key = $field . '_labels';
    for my $container ($source->{$langs_key}, $source->{$labels_key}) {
        next unless ref($container) eq 'HASH';
        my $value = first_text($container->{$current_lang}, $container->{ja}, $container->{en});
        return $value if $value ne '';
    }

    my $localized = $source->{$field};
    if (ref($localized) eq 'HASH') {
        my $value = first_text($localized->{$current_lang}, $localized->{ja}, $localized->{en});
        return $value if $value ne '';
    }

    return first_text($source->{$field}, '');
}

sub render_article_detail {
    my ($article) = @_;
    my $title = escape_html(Mark6::Article::title_for($article, $current_lang, $config));
    my $date = escape_html(format_date($article->{created_at} || ''));
    my $intro = trusted_html(Mark6::Article::description_for($article, $current_lang, $config));
    my $body = trusted_html(Mark6::Article::body_for($article, $current_lang, $config));
    my $tags = render_tags(article_tags_for_lang($article, $current_lang), $article);
    my $image = render_image($article, 'detail-image');
    my $lang_links = render_language_links($article);
    my $kiosk = render_kiosk($article);
    my $article_end = render_free_space('article_end');
    my $after_kiosk = $kiosk ne '' ? render_free_space('after_kiosk') : '';

    $body = $intro if $body eq '';

    return <<"HTML";
<article class="article-detail">
  <a class="back-link" href="@{[escape_attr(article_list_url('', Mark6::Article::node_for($article, $config)))]}">@{[escape_html((public_nav_labels())[1])]}</a>
  <div class="meta">$date</div>
  $lang_links
  <h1>$title</h1>
  $image
  <div class="body">$body</div>
  $article_end
  $kiosk
  $after_kiosk
  $tags
</article>
HTML
}

sub render_fixed_page {
    my ($page) = @_;
    my $title = escape_html(Mark6::Article::title_for($page, $current_lang, $config));
    my $body = trusted_html(Mark6::Article::body_for($page, $current_lang, $config));
    my $description = trusted_html(Mark6::Article::description_for($page, $current_lang, $config));
    my $image = render_image($page, 'detail-image');
    my $lang_links = render_language_links($page);
    $body = $description if $body eq '';

    return <<"HTML";
<article class="article-detail fixed-page">
  $lang_links
  <h1>$title</h1>
  $image
  <div class="body">$body</div>
</article>
HTML
}

sub render_free_space {
    my ($slot) = @_;
    return '' unless $slot =~ /\A(?:home_bottom|after_kiosk|article_end)\z/;
    my $all = ref($config->{free_space}) eq 'HASH' ? $config->{free_space} : {};
    my $localized = ref($all->{$slot}) eq 'HASH' ? $all->{$slot} : {};
    my $entry = ref($localized->{$current_lang}) eq 'HASH' ? $localized->{$current_lang} : {};
    return '' unless truthy($entry->{enabled});
    return '' unless defined($entry->{html}) && $entry->{html} =~ /\S/;
    my $class = $slot;
    $class =~ s/_/-/g;
    return '<section class="free-space free-space-' . $class . '">' . trusted_html($entry->{html}) . '</section>';
}

sub render_kiosk {
    my ($article) = @_;
    my $kiosk = config_for_lang($article->{kiosk}, $current_lang);
    return render_kiosk_config($kiosk);
}

sub render_kiosk_config {
    my ($kiosk) = @_;
    return '' unless truthy($kiosk->{enabled});
    return '' unless ref($kiosk->{items}) eq 'ARRAY';

    my @items;
    for my $item (@{$kiosk->{items}}) {
        next unless ref($item) eq 'HASH';
        my $type = item_type($item);
        my $label = first_text($item->{label}, $item->{keyword}, $item->{url});
        next if $label eq '';

        my ($href, $detail, $action);
        if ($type eq 'amazon') {
            my $keyword = first_text($item->{keyword}, $item->{label});
            next if $keyword eq '';
            $href = kiosk_search_url($keyword);
            $detail = $label eq $keyword
                ? ''
                : '<span class="kiosk-keyword">' . escape_html(kiosk_keyword_label()) . ': ' . escape_html($keyword) . '</span>';
            $action = kiosk_action_label('amazon');
        }
        elsif ($type eq 'url') {
            next unless valid_url($item->{url});
            $href = $item->{url};
            $detail = '';
            $action = kiosk_action_label('url');
        }
        else {
            next;
        }

        push @items, '<li><a class="kiosk-card" href="' . escape_attr($href) . '" target="_blank" rel="noopener noreferrer sponsored">'
            . '<span class="kiosk-label">' . escape_html($label) . '</span>'
            . $detail
            . '<span class="kiosk-action">' . escape_html($action) . '</span>'
            . '</a></li>';
    }
    return '' unless @items;

    my $heading = escape_html(kiosk_heading());
    return '<section class="kiosk"><h2>' . $heading . '</h2><ul class="kiosk-list">' . join('', @items) . '</ul></section>';
}

sub render_home_kiosk {
    my ($home, $articles) = @_;
    my $kiosk = config_for_lang($home->{kiosk}, $current_lang);
    return '' unless truthy($kiosk->{enabled});

    my $mode = ($kiosk->{mode} || 'manual') eq 'auto' ? 'auto' : 'manual';
    if ($mode eq 'auto') {
        my @items = auto_home_kiosk_items($articles);
        return render_kiosk_config({ enabled => 1, items => \@items });
    }

    return render_kiosk_config($kiosk);
}

sub auto_home_kiosk_items {
    my ($articles) = @_;
    my @items;
    my %seen;

    for my $article (@{$articles || []}) {
        my $kiosk = config_for_lang($article->{kiosk}, $current_lang);
        next unless truthy($kiosk->{enabled});
        next unless ref($kiosk->{items}) eq 'ARRAY';
        for my $item (@{$kiosk->{items}}) {
            next unless ref($item) eq 'HASH';
            my $type = item_type($item);
            my $label = first_text($item->{label}, $item->{keyword}, $item->{url});
            my $target = $type eq 'url' ? ($item->{url} || '') : first_text($item->{keyword}, $item->{label});
            next if $label eq '' || $target eq '';
            next if $type eq 'url' && !valid_url($target);
            next if $type eq '';
            my $key = lc "$type\0$label\0$target";
            next if $seen{$key}++;
            push @items, { %{$item}, type => $type, label => $label };
            return @items if @items >= 5;
        }
    }

    return @items;
}

sub kiosk_heading {
    return $current_lang eq 'ja' ? '売店' : 'Kiosk';
}

sub kiosk_keyword_label {
    return $current_lang eq 'ja' ? '検索' : 'Search';
}

sub kiosk_action_label {
    my ($type) = @_;
    return $current_lang eq 'ja' ? 'リンクを開く' : 'Open link' if ($type || '') eq 'url';
    return $current_lang eq 'ja' ? 'Amazonで探す' : 'Search Amazon';
}

sub kiosk_search_url {
    my ($keyword) = @_;
    my $kiosk = ref($config->{kiosk}) eq 'HASH' ? $config->{kiosk} : {};
    my $provider = $kiosk->{provider} || 'amazon';
    my $encoded = url_encode($keyword);
    my $template = $kiosk->{search_url} || default_kiosk_search_url($provider);
    my $url = $template;
    if ($url =~ /\{encoded_keyword\}/) {
        $url =~ s/\{encoded_keyword\}/$encoded/g;
    }
    else {
        $url .= ($url =~ /\?/ ? '&' : '?') . 'q=' . $encoded;
    }

    my $tag = clean_affiliate_tag($kiosk->{affiliate_tag} || $kiosk->{amazon_affiliate_tag} || '');
    $url .= '&tag=' . url_encode($tag) if $provider eq 'amazon' && $tag ne '';
    return $url;
}

sub default_kiosk_search_url {
    my ($provider) = @_;
    return 'https://www.amazon.co.jp/s?k={encoded_keyword}' if ($provider || '') eq 'amazon';
    return 'https://www.amazon.co.jp/s?k={encoded_keyword}';
}

sub clean_affiliate_tag {
    my ($value) = @_;
    $value = '' unless defined $value;
    $value =~ s/[^0-9A-Za-z_-]//g;
    return $value;
}

sub truthy {
    my ($value) = @_;
    return 0 unless defined $value;
    return 1 if $value eq '1';
    return 1 if "$value" =~ /\Atrue\z/i;
    return 0;
}

sub render_tags {
    my ($tags, $article) = @_;
    return '' unless @{$tags};
    my $node = $article ? Mark6::Article::node_for($article, $config) : '';

    my $links = join ' ', map {
        my $tag = escape_html($_);
        my $url = escape_attr(url_encode($_));
        my $href = escape_attr(article_list_url("tag=$url", $node));
        qq|<a href="$href">$tag</a>|;
    } @{$tags};

    return qq|<nav class="tags">$links</nav>|;
}

sub article_tags_for_lang {
    my ($article, $lang) = @_;
    return Mark6::Article::tags_for_lang($article, $lang, $config);
}

sub article_has_tag {
    my ($article, $tag) = @_;
    return 0 unless defined $tag && $tag ne '';
    my %tags;
    for my $candidate (@{article_tags_for_lang($article, $current_lang)}, @{$article->{tags} || []}) {
        next unless defined $candidate && $candidate ne '';
        $tags{$candidate} = 1;
    }
    return $tags{$tag} ? 1 : 0;
}

sub render_image {
    my ($article, $class) = @_;
    my $image = $article->{image} || '';
    return '' unless safe_image_path($image);

    my $src = escape_attr(image_src($image));
    my $alt = escape_attr(Mark6::Article::title_for($article, $current_lang, $config));
    return qq|<img class="$class" src="$src" alt="$alt" loading="lazy" decoding="async">|;
}

sub home_article_limit {
    my $display = ref($config->{display}) eq 'HASH' ? $config->{display} : {};
    return bounded_number($display->{mini_articles}, 5, 1, 100);
}

sub article_page_limit {
    my $display = ref($config->{display}) eq 'HASH' ? $config->{display} : {};
    return bounded_number($display->{articles_per_page}, 20, 1, 100);
}

sub current_page {
    return bounded_number($in{page}, 1, 1, 9999);
}

sub bounded_number {
    my ($value, $default, $min, $max) = @_;
    return $default unless defined $value && $value =~ /\A[0-9]+\z/;
    return $min if $value < $min;
    return $max if $value > $max;
    return int($value);
}

sub article_sort {
    my $a_order = article_sort_order($a);
    my $b_order = article_sort_order($b);
    my $a_has_order = defined($a->{sort_order}) && $a->{sort_order} =~ /\A[0-9]+\z/;
    my $b_has_order = defined($b->{sort_order}) && $b->{sort_order} =~ /\A[0-9]+\z/;
    return $a_order <=> $b_order if $a_has_order && $b_has_order && $a_order != $b_order;
    return -1 if $a_has_order && !$b_has_order;
    return 1 if !$a_has_order && $b_has_order;
    return ($b->{id} || 0) <=> ($a->{id} || 0);
}

sub article_sort_order {
    my ($article) = @_;
    return int($article->{sort_order}) if defined($article->{sort_order}) && $article->{sort_order} =~ /\A[0-9]+\z/;
    return '';
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
    return $image if external_image_url($image);
    return $image =~ m{\Aimg/} ? site_url($image) : site_url("img/$image");
}

sub safe_image_path {
    my ($value) = @_;
    return 0 unless defined $value && $value ne '';
    return 1 if external_image_url($value);
    return 0 if $value =~ /\.\./;
    return $value =~ /\A[0-9A-Za-z_.\/-]+\z/ ? 1 : 0;
}

sub external_image_url {
    my ($value) = @_;
    return defined $value && $value =~ m{\Ahttps://[^\s<>"']+\z};
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
    for my $page (load_pages()) {
        my $lastmod = format_date($page->{updated_at} || $page->{created_at} || '');
        for my $lang (@supported_langs) {
            push @urls, {
                loc => site_absolute_url(article_url($page, $lang)),
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
    my ($should_count) = Mark6::TrafficFilter->should_count_page_view(
        method     => $ENV{REQUEST_METHOD} || 'GET',
        user_agent => $ENV{HTTP_USER_AGENT} || '',
    );
    return unless $should_count;

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
        traffic       => 'human',
    };
    eval { $store->append_jsonl($event, 'dat', 'logs', 'access.jsonl'); 1 };
}

sub article_meta_description {
    my ($article) = @_;
    my $ai = $article->{ai} || {};
    my $seo = $ai->{seo} || {};
    my $seo_lang = $seo->{lang} || Mark6::Article::default_lang($article, $config);
    my $description = $seo_lang eq $current_lang ? ($seo->{seo_description} || '') : '';
    $description = $ai->{seo_description} || '' if $description eq '';
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
    my $header_links = render_header_navigation();
    my $footer_links = render_configured_navigation('footer');
    my $css_href = escape_attr(asset_url('css/mark6.css') . '?v=6');
    my $favicon_href = escape_attr(asset_url('img/mark6-icon.svg') . '?v=2');
    my $footer_logo = escape_attr(asset_url('img/mark6-logo-light.svg') . '?v=2');
    my $lang_cookie = lang_cookie_header();
    my $safe_page_description = escape_attr($page_description || '');
    my $safe_canonical_url = escape_attr($canonical_url || '');
    my $description_meta = $page_description ne ''
        ? qq|  <meta name="description" content="$safe_page_description">\n|
        : '';
    my $canonical_meta = $canonical_url ne '' ? qq|  <link rel="canonical" href="$safe_canonical_url">\n| : '';
    my $og_type = $article && Mark6::Article::content_type($article) eq 'article' ? 'article' : 'website';
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
      $header_links
    </nav>
    $language_links
  </header>
  <main class="site-main">
    $content
  </main>
  <footer class="site-footer">
    <img src="$footer_logo" alt="MARK6">
    <nav class="footer-nav">$footer_links</nav>
    <span>Powered by MARK6</span>
  </footer>
</body>
</html>
HTML
}

sub render_header_navigation {
    my $area_config = ref($config->{navigation}) eq 'HASH' && ref($config->{navigation}{header}) eq 'HASH'
        ? $config->{navigation}{header} : {};
    my $system = ref($area_config->{system}) eq 'HASH' ? $area_config->{system} : {};
    my @links;
    my $show_home = !exists($system->{home}) || truthy($system->{home});
    my $show_articles = !exists($system->{articles}) || truthy($system->{articles});
    my $show_sections = !exists($system->{sections}) || truthy($system->{sections});
    if ($show_home) {
        my $home_href = escape_attr(lang_url($current_lang));
        my ($home_label) = public_nav_labels();
        push @links, qq|<a href="$home_href">@{[escape_html($home_label)]}</a>|;
    }
    if ($show_articles) {
        my $articles_href = escape_attr(article_list_url());
        my (undef, $articles_label) = public_nav_labels();
        push @links, qq|<a href="$articles_href">@{[escape_html($articles_label)]}</a>|;
    }
    push @links, render_section_nav() if $show_sections;
    my $manual = render_configured_navigation('header');
    push @links, $manual if $manual ne '';
    return join "\n      ", grep { defined $_ && $_ ne '' } @links;
}

sub navigation_area_exists {
    my ($area) = @_;
    return ref($config->{navigation}) eq 'HASH' && exists $config->{navigation}{$area};
}

sub render_configured_navigation {
    my ($area) = @_;
    return '' unless navigation_area_exists($area);
    my $area_config = ref($config->{navigation}{$area}) eq 'HASH' ? $config->{navigation}{$area} : {};
    my $items = ref($area_config->{$current_lang}) eq 'ARRAY' ? $area_config->{$current_lang} : [];
    my @links;
    for my $item (@{$items}) {
        next unless ref($item) eq 'HASH';
        next if exists($item->{enabled}) && !truthy($item->{enabled});
        my $label = first_text($item->{label});
        my $href = navigation_url($item->{url});
        next if $label eq '' || $href eq '';
        my $attrs = $href =~ m{\Ahttps?://}i ? ' target="_blank" rel="noopener noreferrer"' : '';
        push @links, '<a href="' . escape_attr($href) . '"' . $attrs . '>' . escape_html($label) . '</a>';
    }
    return join "\n      ", @links;
}

sub navigation_url {
    my ($url) = @_;
    return '' unless defined $url && $url ne '';
    return $url if $url =~ m{\Ahttps?://[^\s<>"']+\z}i;
    return '' if $url =~ /\.\./;
    return '' unless $url =~ m{\A/[0-9A-Za-z_./?&=%#~-]*\z};

    my $path = $url;
    $path =~ s{\A/+}{};
    return lang_url($current_lang) if $path eq '';
    my ($first) = split m{/}, $path;
    my %supported = map { $_ => 1 } @supported_langs;
    my $default = $config->{site}{default_lang} || $config->{site}{language} || 'ja';
    $path = "$current_lang/$path" unless $supported{$first || ''} || $current_lang eq $default;
    return site_url($path);
}

sub public_nav_labels {
    return $current_lang eq 'ja' ? ('ホーム', '記事', 'タグ') : ('Home', 'Articles', 'Tag');
}

sub render_section_nav {
    my @nodes = nav_nodes();
    return '' unless @nodes;
    my @links;
    for my $node (@nodes) {
        next unless safe_segment($node);
        next if reserved_nav_node($node);
        my $href = escape_attr(site_url("$current_lang/$node/"));
        my $label = escape_html(node_label($node, $current_lang));
        push @links, qq|<a href="$href">$label</a>|;
    }
    return join "\n      ", @links;
}

sub nav_nodes {
    my $nodes = ref($config->{nodes}) eq 'HASH' ? $config->{nodes} : {};
    my @configured = grep {
        safe_segment($_) && !reserved_nav_node($_) && (!exists($nodes->{$_}{nav}) || truthy($nodes->{$_}{nav}))
    } sort keys %{$nodes};
    return @configured if @configured;

    my %seen;
    for my $article (load_articles()) {
        my $node = Mark6::Article::node_for($article, $config);
        $seen{$node}++ if safe_segment($node) && !reserved_nav_node($node);
    }
    return sort { $seen{$b} <=> $seen{$a} || $a cmp $b } keys %seen;
}

sub reserved_nav_node {
    my ($node) = @_;
    $node = lc($node || '');
    return $node =~ /\A(?:article|articles|tag|tags|admin|public|assets)\z/ ? 1 : 0;
}

sub node_label {
    my ($node, $lang) = @_;
    my $nodes = ref($config->{nodes}) eq 'HASH' ? $config->{nodes} : {};
    my $entry = ref($nodes->{$node}) eq 'HASH' ? $nodes->{$node} : {};
    my $labels = ref($entry->{labels}) eq 'HASH' ? $entry->{labels} : {};
    return first_text($labels->{$lang}, $labels->{ja}, $labels->{en}, $node);
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
    my ($query, $node) = @_;
    $node = default_article_node() unless safe_segment($node || '');
    my $url = site_url("$current_lang/$node/");
    return defined $query && $query ne '' ? "$url?$query" : $url;
}

sub render_pagination {
    my ($page, $last_page, $tag, $node) = @_;
    return '' if $last_page <= 1;

    my @links;
    push @links, pagination_link('Prev', $page - 1, $tag, $node, $page <= 1);
    for my $num (1 .. $last_page) {
        if ($num == $page) {
            push @links, '<span aria-current="page">' . escape_html($num) . '</span>';
        }
        else {
            push @links, pagination_link($num, $num, $tag, $node, 0);
        }
    }
    push @links, pagination_link('Next', $page + 1, $tag, $node, $page >= $last_page);

    return '<nav class="pagination" aria-label="Pagination">' . join(' ', @links) . '</nav>';
}

sub pagination_link {
    my ($label, $page, $tag, $node, $disabled) = @_;
    return '<span class="disabled">' . escape_html($label) . '</span>' if $disabled;

    my @query;
    push @query, 'tag=' . url_encode($tag) if defined $tag && $tag ne '';
    push @query, 'page=' . url_encode($page) if $page > 1;
    my $href = escape_attr(article_list_url(join('&', @query), $node));
    return '<a href="' . $href . '">' . escape_html($label) . '</a>';
}

sub default_article_node {
    return $default_article_node_cache if defined $default_article_node_cache;

    my $configured = value_at($config, 'site', 'node') || '';
    return $default_article_node_cache = $configured if safe_segment($configured);
    return $default_article_node_cache = $route->{node} if safe_segment($route->{node} || '');

    my %seen;
    for my $article (load_articles()) {
        my $node = Mark6::Article::node_for($article, $config);
        next unless safe_segment($node);
        $seen{$node}++;
    }

    my @nodes = sort { $seen{$b} <=> $seen{$a} || $a cmp $b } keys %seen;
    return $default_article_node_cache = $nodes[0] if @nodes;
    return $default_article_node_cache = 'articles';
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

sub first_text {
    for my $value (@_) {
        return $value if defined $value && $value ne '';
    }
    return '';
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
