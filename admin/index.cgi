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

Mark6::CGI::print_html(<<"HTML");
<!doctype html>
<html lang="ja">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>MARK6 Admin</title>
  <link rel="stylesheet" href="../public/assets/css/mark6.css">
</head>
<body>
  <header class="site-header">
    <a class="brand" href="index.cgi">MARK6 Admin</a>
    <nav class="site-nav">
      <a href="../public/index.cgi">View Site</a>
      <a href="logout.cgi">Logout</a>
    </nav>
  </header>
  <main class="site-main">
    <section class="article-detail">
      <h1>Dashboard</h1>
      <p>Logged in as <strong>$name</strong> ($rank).</p>
      <div class="admin-menu">
        <a class="button" href="articles.cgi">Manage Articles</a>
        <a class="button secondary" href="media.cgi">Manage Media</a>
      </div>
    </section>
  </main>
</body>
</html>
HTML

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
