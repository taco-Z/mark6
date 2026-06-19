#!/usr/bin/env perl

use strict;
use warnings;
use Cwd qw(abs_path getcwd);
use File::Basename qw(dirname);
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
use Mark6::Lang;
use Mark6::Root;

my $ROOT = $ENV{MARK6_ROOT} || Mark6::Root::default_root(findbin => $FindBin::Bin, script => $0, marker => 'dat/users.json');
my $auth = Mark6::Auth->new(root => $ROOT);
my $store = Mark6::DataStore->new(root => $ROOT);
my $lang = Mark6::Lang->new(root => $ROOT);
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

if (($ENV{REQUEST_METHOD} || 'GET') eq 'POST') {
    unless ($auth->verify_csrf($session, $params{csrf_token} || '')) {
        render_page($lang->t('admin.common.csrf_error', 'CSRF Error'), '<p class="error">' . h($lang->t('admin.common.invalid_form_token', 'Invalid form token.')) . '</p>');
        exit;
    }

    save_home();
    Mark6::CGI::redirect('home.cgi?saved=1');
    exit;
}

render_home_editor();

sub render_home_editor {
    my $home = load_home();
    my $csrf = Mark6::CGI::escape_html($session->{csrf_token} || '');
    my $saved = ($params{saved} || '') eq '1' ? '<p class="notice">' . h($lang->t('admin.home.saved', 'Home saved.')) . '</p>' : '';

    my $title = Mark6::CGI::escape_html($home->{title} || '');
    my $body = Mark6::CGI::escape_html($home->{body} || '');
    my $show_articles_checked = $home->{show_articles} ? 'checked' : '';
    my $page_title = h($lang->t('admin.common.home', 'Home'));
    my $dashboard_label = h($lang->t('admin.common.dashboard', 'Dashboard'));
    my $title_label = h($lang->t('admin.home.title_label', 'Title'));
    my $body_label = h($lang->t('admin.home.body_html', 'Body HTML'));
    my $show_latest_label = h($lang->t('admin.home.show_latest', 'Show latest articles on home'));
    my $save_label = h($lang->t('admin.home.save', 'Save Home'));

    render_page($lang->t('admin.common.home', 'Home'), <<"HTML");
<section class="article-detail">
  <a class="back-link" href="index.cgi">$dashboard_label</a>
  <h1>$page_title</h1>
  $saved
  <form class="admin-form" method="post" action="home.cgi">
    <input type="hidden" name="csrf_token" value="$csrf">
    <label>$title_label<br><input name="title" type="text" value="$title" required></label>
    <label>$body_label<br><textarea name="body" rows="16">$body</textarea></label>
    <label><input name="show_articles" type="checkbox" value="1" $show_articles_checked> $show_latest_label</label>
    <button type="submit">$save_label</button>
  </form>
</section>
HTML
}

sub save_home {
    my $home = load_home();
    $home->{title} = $params{title} || 'Home';
    $home->{body} = $params{body} || '';
    $home->{show_articles} = ($params{show_articles} || '') eq '1' ? JSON::PP::true : JSON::PP::false;
    $home->{updated_at} = iso_now();
    $store->write_json($home, 'dat', 'home.json');
}

sub load_home {
    return $store->read_json('dat', 'home.json') || {
        title => 'Home',
        body => '',
        show_articles => JSON::PP::true,
        updated_at => '',
    };
}

sub render_page {
    my ($title, $content) = @_;
    Mark6::Admin::render_page(
        title   => $title,
        active  => 'home',
        root    => $ROOT,
        lang    => $lang,
        content => $content,
    );
}

sub h {
    return Mark6::CGI::escape_html($_[0] || '');
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
