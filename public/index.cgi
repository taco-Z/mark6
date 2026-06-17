#!/usr/bin/env perl

use strict;
use warnings;
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

my $ROOT = $ENV{MARK6_ROOT} || default_root();
my $store = Mark6::DataStore->new(root => $ROOT);
my %in = parse_query();

my $config = $store->read_json('dat', 'config.json') || {};
my $home   = $store->read_json('dat', 'home.json') || {};
my $order  = $in{order} || 'index';

my $site_title = value_at($config, 'site', 'title') || 'MARK6';
my $content;
my $page_title = $site_title;

if ($order eq 'focus') {
    my $article = find_article($in{tar} || '');
    if ($article) {
        $page_title = ($article->{title} || 'Article') . " - $site_title";
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

print encode('UTF-8', render_page($page_title, $site_title, $content));

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
        push @articles, $article;
    }

    return sort { ($b->{id} || 0) <=> ($a->{id} || 0) } @articles;
}

sub find_article {
    my ($id) = @_;
    return undef unless $id =~ /\A[0-9A-Za-z_-]+\z/;

    my $article = $store->read_json('dat', 'articles', "$id.json");
    return undef unless $article && ($article->{status} || '') eq 'published';
    return $article;
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
    my $id = escape_attr($article->{id} || '');
    my $title = escape_html($article->{title} || 'Untitled');
    my $date = escape_html(format_date($article->{created_at} || ''));
    my $intro = trusted_html($article->{intro} || '');
    my $tags = render_tags($article->{tags} || []);
    my $image = render_image($article, 'summary-image');

    return <<"HTML";
<article class="article-summary">
  $image
  <div class="summary-main">
    <div class="meta">$date</div>
    <h3><a href="index.cgi?order=focus&amp;tar=$id">$title</a></h3>
    <div class="intro">$intro</div>
    $tags
  </div>
</article>
HTML
}

sub render_article_detail {
    my ($article) = @_;
    my $title = escape_html($article->{title} || 'Untitled');
    my $date = escape_html(format_date($article->{created_at} || ''));
    my $intro = trusted_html($article->{intro} || '');
    my $body = trusted_html($article->{body} || '');
    my $tags = render_tags($article->{tags} || []);
    my $image = render_image($article, 'detail-image');

    $body = $intro if $body eq '';

    return <<"HTML";
<article class="article-detail">
  <a class="back-link" href="index.cgi?order=article">Articles</a>
  <div class="meta">$date</div>
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
        qq|<a href="index.cgi?order=article&amp;tag=$url">$tag</a>|;
    } @{$tags};

    return qq|<nav class="tags">$links</nav>|;
}

sub render_image {
    my ($article, $class) = @_;
    my $image = $article->{image} || '';
    return '' unless $image ne '' && $image =~ /\A[0-9A-Za-z_.-]+\z/;

    my $src = escape_attr("../img/$image");
    my $alt = escape_attr($article->{title} || '');
    return qq|<img class="$class" src="$src" alt="$alt">|;
}

sub render_not_found {
    return <<'HTML';
<section class="not-found">
  <h1>Article not found</h1>
  <p>The requested article is not available.</p>
  <p><a href="index.cgi">Back to home</a></p>
</section>
HTML
}

sub render_page {
    my ($page_title, $site_title, $content) = @_;
    my $safe_page_title = escape_html($page_title);
    my $safe_site_title = escape_html($site_title);

    return <<"HTML";
Content-Type: text/html; charset=UTF-8

<!doctype html>
<html lang="ja">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$safe_page_title</title>
  <link rel="stylesheet" href="assets/css/mark6.css">
</head>
<body>
  <header class="site-header">
    <a class="brand" href="index.cgi">$safe_site_title</a>
    <nav class="site-nav">
      <a href="index.cgi">Home</a>
      <a href="index.cgi?order=article">Articles</a>
    </nav>
  </header>
  <main class="site-main">
    $content
  </main>
  <footer class="site-footer">Powered by MARK6</footer>
</body>
</html>
HTML
}

sub trusted_html {
    my ($html) = @_;
    return $html;
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
