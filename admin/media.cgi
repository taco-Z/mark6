#!/usr/bin/env perl

use strict;
use warnings;
use Cwd qw(abs_path getcwd);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use FindBin;
use JSON::PP ();

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
use Mark6::Admin;
use Mark6::CGI qw();
use Mark6::DataStore;

my $ROOT = $ENV{MARK6_ROOT} || default_root();
my $auth = Mark6::Auth->new(root => $ROOT);
my $store = Mark6::DataStore->new(root => $ROOT);
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

my $method = $ENV{REQUEST_METHOD} || 'GET';

if ($method eq 'POST') {
    my %form = read_multipart_form();
    unless ($auth->verify_csrf($session, $form{csrf_token}{value} || '')) {
        render_page('CSRF Error', '<p class="error">Invalid form token.</p>');
        exit;
    }

    my $command = $form{command}{value} || '';
    if ($command eq 'upload') {
        upload_media($form{file});
        Mark6::CGI::redirect('media.cgi');
        exit;
    }
    if ($command eq 'delete') {
        delete_media($form{id}{value} || '');
        Mark6::CGI::redirect('media.cgi');
        exit;
    }
}

render_list();

sub render_list {
    my @media = load_media();
    my $csrf = Mark6::CGI::escape_html($session->{csrf_token} || '');
    my $items = @media ? join("\n", map { media_card($_) } @media) : '<p class="empty">No media yet.</p>';

    render_page('Media', <<"HTML");
<section class="article-detail">
  <a class="back-link" href="index.cgi">Dashboard</a>
  <h1>Media</h1>
  <form class="media-upload" method="post" action="media.cgi" enctype="multipart/form-data">
    <input type="hidden" name="command" value="upload">
    <input type="hidden" name="csrf_token" value="$csrf">
    <label>Image file<br><input name="file" type="file" accept="image/jpeg,image/png,image/gif,image/webp" required></label>
    <button type="submit">Upload</button>
  </form>
  <div class="media-grid">$items</div>
</section>
HTML
}

sub media_card {
    my ($item) = @_;
    my $id = Mark6::CGI::escape_html($item->{id} || '');
    my $path = Mark6::CGI::escape_html($item->{path} || '');
    my $url = Mark6::CGI::escape_html("../$path");
    my $name = Mark6::CGI::escape_html($item->{original_filename} || $item->{filename} || '');
    my $size = Mark6::CGI::escape_html($item->{size} || 0);
    my $csrf = Mark6::CGI::escape_html($session->{csrf_token} || '');
    my $img_tag = Mark6::CGI::escape_html(qq|<img src="../$path" alt="">|);

    return <<"HTML";
<article class="media-card">
  <img src="$url" alt="$name">
  <div class="media-card-body">
    <strong>$name</strong>
    <div class="meta">$size bytes</div>
    <label>Path<input type="text" value="$path" readonly onclick="this.select()"></label>
    <label>HTML<input type="text" value="$img_tag" readonly onclick="this.select()"></label>
    <form method="post" action="media.cgi" enctype="multipart/form-data">
      <input type="hidden" name="command" value="delete">
      <input type="hidden" name="id" value="$id">
      <input type="hidden" name="csrf_token" value="$csrf">
      <button type="submit">Delete</button>
    </form>
  </div>
</article>
HTML
}

sub upload_media {
    my ($file) = @_;
    die "No file uploaded" unless $file && length($file->{content} || '') > 0;

    my $original = sanitize_original_name($file->{filename} || 'image');
    my ($ext) = $original =~ /(\.[A-Za-z0-9]+)\z/;
    $ext = lc($ext || '');
    die "Unsupported image type" unless $ext =~ /\A\.(?:jpg|jpeg|png|gif|webp)\z/;
    die "File is too large" if length($file->{content}) > 8 * 1024 * 1024;

    my @t = gmtime(time);
    my $year = $t[5] + 1900;
    my $month = sprintf('%02d', $t[4] + 1);
    my $id = sprintf('%04d%02d%02d%02d%02d%02d-%04d', $year, $t[4] + 1, $t[3], $t[2], $t[1], $t[0], int(rand(10_000)));
    my $filename = "$id-$original";
    my $relative = "img/uploads/$year/$month/$filename";
    my $absolute = "$ROOT/$relative";

    make_path(dirname($absolute));
    open my $fh, '>:raw', $absolute or die "Cannot write $absolute: $!";
    print {$fh} $file->{content};
    close $fh;

    my $item = {
        id                => $id,
        status            => 'active',
        filename          => $filename,
        original_filename => $original,
        path              => $relative,
        mime              => $file->{content_type} || '',
        size              => length($file->{content}),
        created_at        => iso_now(),
        uploaded_by       => $user->{id},
    };

    $store->write_json($item, 'dat', 'media', "$id.json");
}

sub delete_media {
    my ($id) = @_;
    return unless $id =~ /\A[0-9A-Za-z_-]+\z/;
    my $item = $store->read_json('dat', 'media', "$id.json") or return;
    $item->{status} = 'deleted';
    $item->{updated_at} = iso_now();
    $store->write_json($item, 'dat', 'media', "$id.json");
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

sub read_multipart_form {
    my $content_type = $ENV{CONTENT_TYPE} || '';
    die "Expected multipart/form-data" unless $content_type =~ /boundary=(?:"([^"]+)"|([^;]+))/;
    my $boundary = $1 || $2;
    my $length = $ENV{CONTENT_LENGTH} || 0;
    read(STDIN, my $body, $length) if $length > 0;

    my %form;
    my $marker = "--$boundary";
    for my $part (split(/\Q$marker\E/, $body || '')) {
        next if $part =~ /\A(?:--)?\s*\z/;
        $part =~ s/\A\r\n//;
        $part =~ s/\r\n\z//;
        my ($raw_headers, $content) = split(/\r\n\r\n/, $part, 2);
        next unless defined $raw_headers && defined $content;

        my %headers = map {
            my ($key, $value) = split(/:\s*/, $_, 2);
            (lc($key || '') => $value || '');
        } split(/\r\n/, $raw_headers);

        my $disposition = $headers{'content-disposition'} || '';
        next unless $disposition =~ /name="([^"]+)"/;
        my $name = $1;
        my ($filename) = $disposition =~ /filename="([^"]*)"/;

        if (defined $filename && $filename ne '') {
            $form{$name} = {
                filename     => $filename,
                content      => $content,
                content_type => $headers{'content-type'} || '',
            };
        }
        else {
            $content =~ s/\r\n\z//;
            $form{$name} = { value => Mark6::CGI::url_decode($content) };
        }
    }

    return %form;
}

sub sanitize_original_name {
    my ($name) = @_;
    $name =~ s#.*[\\/]##;
    $name =~ s/[^0-9A-Za-z_.-]+/-/g;
    $name =~ s/\A-+|-+\z//g;
    return $name || 'image';
}

sub render_page {
    my ($title, $content) = @_;
    Mark6::Admin::render_page(
        title   => $title,
        active  => 'media',
        content => $content,
    );
}

sub iso_now {
    my @t = gmtime(time);
    return sprintf('%04d-%02d-%02dT%02d:%02d:%02dZ',
        $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0]);
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
