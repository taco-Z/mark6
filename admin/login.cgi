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
use Mark6::Lang;
use Mark6::Root;

my $ROOT = $ENV{MARK6_ROOT} || Mark6::Root::default_root(findbin => $FindBin::Bin, script => $0, marker => 'dat/users.json');
my $auth = Mark6::Auth->new(root => $ROOT);
my $lang = Mark6::Lang->new(root => $ROOT);
my %params = Mark6::CGI::request_params();
my $method = $ENV{REQUEST_METHOD} || 'GET';

unless (has_users()) {
    Mark6::CGI::redirect('setup.cgi');
    exit;
}

if ($method eq 'POST') {
    my $user = $auth->authenticate($params{name} || '', $params{password} || '');

    if ($user) {
        my $session = $auth->create_session(
            user_id    => $user->{id},
            ip         => $ENV{REMOTE_ADDR} || '',
            user_agent => $ENV{HTTP_USER_AGENT} || '',
        );
        Mark6::CGI::redirect(
            'index.cgi',
            $auth->session_cookie_header($session->{session_id}, secure => secure_cookie()),
        );
        exit;
    }

    render_login($lang->t('admin.login.failed', 'Login failed.'));
    exit;
}

render_login('');

sub has_users {
    my $users = $auth->load_users;
    return scalar @{$users->{users} || []};
}

sub render_login {
    my ($message) = @_;
    my $message_html = $message ? '<p class="error">' . Mark6::CGI::escape_html($message) . '</p>' : '';
    my $html_lang = h($lang->code);
    my $page_title = h($lang->t('admin.login.title', 'MARK6 Login'));
    my $user_id_label = h($lang->t('admin.login.user_id', 'User ID'));
    my $password_label = h($lang->t('admin.login.password', 'Password'));
    my $submit_label = h($lang->t('admin.login.submit', 'Login'));

    Mark6::CGI::print_html(<<"HTML");
<!doctype html>
<html lang="$html_lang">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$page_title</title>
  <link rel="stylesheet" href="../public/assets/css/mark6.css">
</head>
<body>
  <main class="site-main admin-login">
    <section class="article-detail">
      <h1>$page_title</h1>
      $message_html
      <form method="post" action="login.cgi">
        <label>$user_id_label<br><input name="name" type="text" autocomplete="username" required></label>
        <br><br>
        <label>$password_label<br><input name="password" type="password" autocomplete="current-password" required></label>
        <br><br>
        <button type="submit">$submit_label</button>
      </form>
    </section>
  </main>
</body>
</html>
HTML
}

sub secure_cookie {
    return ($ENV{HTTPS} || '') eq 'on' || ($ENV{MARK6_SECURE_COOKIE} || '') eq '1';
}

sub h {
    return Mark6::CGI::escape_html($_[0] || '');
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
