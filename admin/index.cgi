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
use Mark6::Admin;
use Mark6::CGI qw();
use Mark6::Lang;

my $ROOT = $ENV{MARK6_ROOT} || default_root();
my $auth = Mark6::Auth->new(root => $ROOT);
my %cookies = Mark6::CGI::cookies();
my $session = $auth->read_session($cookies{mark6_session} || '');

unless (has_users()) {
    Mark6::CGI::redirect('setup.cgi');
    exit;
}

unless ($session) {
    Mark6::CGI::redirect('login.cgi');
    exit;
}

my $user = $auth->find_user_by_id($session->{user_id});
unless ($user) {
    Mark6::CGI::redirect('login.cgi', $auth->clear_session_cookie_header);
    exit;
}

my $name = Mark6::CGI::escape_html($user->{name});
my $rank = Mark6::CGI::escape_html($user->{rank});
my $lang = Mark6::Lang->new(root => $ROOT);
my $dashboard_title = Mark6::CGI::escape_html($lang->t('admin.dashboard.title', 'Dashboard'));
my $logged_in_as = Mark6::CGI::escape_html($lang->t('admin.dashboard.logged_in_as', 'Logged in as'));
my $edit_home = Mark6::CGI::escape_html($lang->t('admin.dashboard.edit_home', 'Edit Home'));
my $manage_articles = Mark6::CGI::escape_html($lang->t('admin.dashboard.manage_articles', 'Manage Articles'));
my $manage_media = Mark6::CGI::escape_html($lang->t('admin.dashboard.manage_media', 'Manage Media'));
my $site_settings = Mark6::CGI::escape_html($lang->t('admin.dashboard.site_settings', 'Site Settings'));

Mark6::Admin::render_page(
    title => $dashboard_title,
    active => 'dashboard',
    root => $ROOT,
    lang => $lang,
    content => <<"HTML",
<section class="article-detail">
      <h1>$dashboard_title</h1>
      <p>$logged_in_as: <strong>$name</strong> ($rank)</p>
      <div class="admin-menu">
        <a class="button" href="home.cgi">$edit_home</a>
        <a class="button" href="articles.cgi">$manage_articles</a>
        <a class="button secondary" href="media.cgi">$manage_media</a>
        <a class="button secondary" href="settings.cgi">$site_settings</a>
      </div>
</section>
HTML
);

sub has_users {
    my $users = $auth->load_users;
    return scalar @{$users->{users} || []};
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
