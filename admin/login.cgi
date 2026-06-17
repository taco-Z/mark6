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
my %params = Mark6::CGI::request_params();
my $method = $ENV{REQUEST_METHOD} || 'GET';

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

    render_login('Login failed.');
    exit;
}

render_login('');

sub render_login {
    my ($message) = @_;
    my $message_html = $message ? '<p class="error">' . Mark6::CGI::escape_html($message) . '</p>' : '';

    Mark6::CGI::print_html(<<"HTML");
<!doctype html>
<html lang="ja">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>MARK6 Login</title>
  <link rel="stylesheet" href="../public/assets/css/mark6.css">
</head>
<body>
  <main class="site-main admin-login">
    <section class="article-detail">
      <h1>MARK6 Login</h1>
      $message_html
      <form method="post" action="login.cgi">
        <label>User ID<br><input name="name" type="text" autocomplete="username" required></label>
        <br><br>
        <label>Password<br><input name="password" type="password" autocomplete="current-password" required></label>
        <br><br>
        <button type="submit">Login</button>
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

