#!/usr/bin/env perl

use strict;
use warnings;
use Cwd qw(abs_path getcwd);
use File::Basename qw(dirname);
use FindBin;

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

use Mark6::Auth;
use Mark6::CGI qw();
use Mark6::DataStore;

my $ROOT = $ENV{MARK6_ROOT} || default_root();
my $auth = Mark6::Auth->new(root => $ROOT);
my $store = Mark6::DataStore->new(root => $ROOT);
my %params = Mark6::CGI::request_params();
my %cookies = Mark6::CGI::cookies();
my $session = $auth->read_session($cookies{mark6_session} || '');

unless ($session) {
    Mark6::CGI::redirect('login.cgi');
    exit;
}

my $user = $auth->find_user_by_id($session->{user_id});
unless ($user) {
    Mark6::CGI::redirect('login.cgi', $auth->clear_session_cookie_header);
    exit;
}

my $command = $params{command} || 'list';

if (($ENV{REQUEST_METHOD} || 'GET') eq 'POST') {
    unless ($auth->verify_csrf($session, $params{csrf_token} || '')) {
        render_page('CSRF Error', '<p class="error">Invalid form token.</p>');
        exit;
    }

    if ($command eq 'save') {
        save_article();
        Mark6::CGI::redirect('articles.cgi');
        exit;
    }

    if ($command eq 'delete') {
        delete_article($params{id} || '');
        Mark6::CGI::redirect('articles.cgi');
        exit;
    }
}

if ($command eq 'new') {
    render_form(blank_article(), 'New Article');
}
elsif ($command eq 'edit') {
    my $article = load_article($params{id} || '');
    $article ? render_form($article, 'Edit Article') : render_page('Not Found', '<p class="error">Article not found.</p>');
}
else {
    render_list();
}

sub render_list {
    my @articles = grep { ($_->{status} || '') ne 'deleted' } load_articles();
    my $rows = @articles ? join("\n", map { article_row($_) } @articles) : '<p class="empty">No articles yet.</p>';

    render_page('Articles', <<"HTML");
<section class="article-detail">
  <div class="admin-toolbar"><a class="button" href="articles.cgi?command=new">New Article</a></div>
  <h1>Articles</h1>
  <div class="admin-list">$rows</div>
</section>
HTML
}

sub article_row {
    my ($article) = @_;
    my $id = Mark6::CGI::escape_html($article->{id} || '');
    my $title = Mark6::CGI::escape_html($article->{title} || 'Untitled');
    my $status = Mark6::CGI::escape_html($article->{status} || 'draft');
    my $date = Mark6::CGI::escape_html(format_date($article->{created_at} || ''));
    my $csrf = Mark6::CGI::escape_html($session->{csrf_token} || '');

    return <<"HTML";
<article class="admin-row">
  <div>
    <strong>$title</strong>
    <div class="meta">$status / $date / ID $id</div>
  </div>
  <div class="admin-actions">
    <a href="../public/index.cgi?order=focus&amp;tar=$id">View</a>
    <a href="articles.cgi?command=edit&amp;id=$id">Edit</a>
    <form method="post" action="articles.cgi">
      <input type="hidden" name="command" value="delete">
      <input type="hidden" name="id" value="$id">
      <input type="hidden" name="csrf_token" value="$csrf">
      <button type="submit">Delete</button>
    </form>
  </div>
</article>
HTML
}

sub render_form {
    my ($article, $heading) = @_;
    my $id = Mark6::CGI::escape_html($article->{id} || '');
    my $title = Mark6::CGI::escape_html($article->{title} || '');
    my $tags = Mark6::CGI::escape_html(join(', ', @{$article->{tags} || []}));
    my $image = Mark6::CGI::escape_html($article->{image} || '');
    my $intro = Mark6::CGI::escape_html($article->{intro} || '');
    my $body = Mark6::CGI::escape_html($article->{body} || '');
    my $media_options = media_options($article->{image} || '');
    my $csrf = Mark6::CGI::escape_html($session->{csrf_token} || '');
    my $status = $article->{status} || 'draft';
    my $draft_selected = $status eq 'draft' ? 'selected' : '';
    my $published_selected = $status eq 'published' ? 'selected' : '';

    render_page($heading, <<"HTML");
<section class="article-detail">
  <a class="back-link" href="articles.cgi">Articles</a>
  <h1>$heading</h1>
  <form class="admin-form" method="post" action="articles.cgi">
    <input type="hidden" name="command" value="save">
    <input type="hidden" name="id" value="$id">
    <input type="hidden" name="csrf_token" value="$csrf">
    <label>Title<br><input name="title" type="text" value="$title" required></label>
    <label>Status<br>
      <select name="status">
        <option value="draft" $draft_selected>Draft</option>
        <option value="published" $published_selected>Published</option>
      </select>
    </label>
    <label>Tags<br><input name="tags" type="text" value="$tags"></label>
    <label>Main image<br>
      <select name="image">
        <option value="">No image</option>
        $media_options
      </select>
    </label>
    <label>Image path<br><input name="image_manual" type="text" value="$image"></label>
    <label>Intro HTML<br><textarea name="intro" rows="6">$intro</textarea></label>
    <label>Body HTML<br><textarea name="body" rows="12">$body</textarea></label>
    <button type="submit">Save</button>
  </form>
</section>
HTML
}

sub save_article {
    my $id = $params{id} || time;
    die "Invalid article id" unless $id =~ /\A[0-9A-Za-z_-]+\z/;

    my $existing = load_article($id) || {};
    my $now = iso_now();
    my $article = {
        %{$existing},
        id         => "$id",
        type       => 'article',
        status     => normalize_status($params{status}),
        title      => $params{title} || 'Untitled',
        slug       => $existing->{slug} || '',
        tags       => parse_tags($params{tags} || ''),
        image      => safe_image_path($params{image_manual} || $params{image} || ''),
        intro      => $params{intro} || '',
        body       => $params{body} || '',
        writer_id  => $existing->{writer_id} || $user->{id},
        created_at => $existing->{created_at} || $now,
        updated_at => $now,
        ai         => $existing->{ai} || {
            summary           => '',
            suggested_tags    => [],
            seo_description   => '',
            last_processed_at => '',
        },
    };

    $store->write_json($article, 'dat', 'articles', "$id.json");
}

sub delete_article {
    my ($id) = @_;
    return unless $id =~ /\A[0-9A-Za-z_-]+\z/;
    my $article = load_article($id) or return;
    $article->{status} = 'deleted';
    $article->{updated_at} = iso_now();
    $store->write_json($article, 'dat', 'articles', "$id.json");
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
        push @articles, $article if $article;
    }

    return sort { ($b->{id} || 0) <=> ($a->{id} || 0) } @articles;
}

sub load_article {
    my ($id) = @_;
    return undef unless $id =~ /\A[0-9A-Za-z_-]+\z/;
    return $store->read_json('dat', 'articles', "$id.json");
}

sub blank_article {
    return {
        id => '',
        status => 'draft',
        title => '',
        tags => [],
        image => '',
        intro => '',
        body => '',
    };
}

sub render_page {
    my ($title, $content) = @_;
    my $safe_title = Mark6::CGI::escape_html($title);

    Mark6::CGI::print_html(<<"HTML");
<!doctype html>
<html lang="ja">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$safe_title - MARK6 Admin</title>
  <link rel="stylesheet" href="../public/assets/css/mark6.css">
</head>
<body>
  <header class="site-header">
    <a class="brand" href="index.cgi">MARK6 Admin</a>
    <nav class="site-nav">
      <a href="index.cgi">Dashboard</a>
      <a href="../public/index.cgi">View Site</a>
      <a href="logout.cgi">Logout</a>
    </nav>
  </header>
  <main class="site-main">$content</main>
</body>
</html>
HTML
}

sub parse_tags {
    my ($value) = @_;
    my @tags = grep { $_ ne '' } map {
        my $tag = $_;
        $tag =~ s/^\s+|\s+$//g;
        $tag;
    } split /,/, $value;
    return \@tags;
}

sub normalize_status {
    my ($status) = @_;
    return $status eq 'published' ? 'published' : 'draft';
}

sub media_options {
    my ($selected) = @_;
    my @media = load_media();
    return '' unless @media;

    return join "\n", map {
        my $path = $_->{path} || '';
        my $label = $_->{original_filename} || $_->{filename} || $path;
        my $safe_path = Mark6::CGI::escape_html($path);
        my $safe_label = Mark6::CGI::escape_html($label);
        my $is_selected = $path eq $selected ? 'selected' : '';
        qq|<option value="$safe_path" $is_selected>$safe_label</option>|;
    } @media;
}

sub load_media {
    my $dir = "$ROOT/dat/media";
    return () unless -d $dir;

    opendir my $dh, $dir or die "Cannot open $dir: $!";
    my @files = grep { /\.json\z/ } readdir $dh;
    closedir $dh;

    my @media;
    for my $file (@files) {
        my $item = $store->read_json('dat', 'media', $file);
        next unless $item && ($item->{status} || 'active') eq 'active';
        push @media, $item;
    }

    return sort { ($b->{created_at} || '') cmp ($a->{created_at} || '') } @media;
}

sub safe_image_path {
    my ($value) = @_;
    return '' unless defined $value;
    return '' if $value =~ /\.\./;
    return $value =~ /\A[0-9A-Za-z_.\/-]+\z/ ? $value : '';
}

sub iso_now {
    my @t = gmtime(time);
    return sprintf('%04d-%02d-%02dT%02d:%02d:%02dZ',
        $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0]);
}

sub format_date {
    my ($iso) = @_;
    return '' unless $iso =~ /\A(\d{4})-(\d{2})-(\d{2})/;
    return "$1-$2-$3";
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
        return $candidate if -e "$candidate/dat/users.json";
    }

    return "$FindBin::Bin/..";
}
