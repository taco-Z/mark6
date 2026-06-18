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
use Mark6::CGI qw();
use Mark6::DataStore;
use Mark6::Root;

my $ROOT = $ENV{MARK6_ROOT} || Mark6::Root::default_root(findbin => $FindBin::Bin, script => $0);
my $auth = Mark6::Auth->new(root => $ROOT);
my $store = Mark6::DataStore->new(root => $ROOT);
my %params = Mark6::CGI::request_params();
my $method = $ENV{REQUEST_METHOD} || 'GET';

if (has_users()) {
    Mark6::CGI::redirect('login.cgi');
    exit;
}

if ($method eq 'POST') {
    my @errors = validate_setup();
    if (@errors) {
        render_setup(\@errors);
        exit;
    }

    initialize_site();
    my $user = $auth->create_user(
        name     => $params{name},
        password => $params{password},
        rank     => 'master',
    );
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

render_setup([]);

sub has_users {
    my $users = $auth->load_users;
    return scalar @{$users->{users} || []};
}

sub validate_setup {
    my @errors;
    push @errors, 'Site title is required.' unless ($params{site_title} || '') ne '';
    push @errors, 'User ID is required.' unless ($params{name} || '') ne '';
    push @errors, 'Password is required.' unless ($params{password} || '') ne '';
    push @errors, 'Password confirmation does not match.' unless ($params{password} || '') eq ($params{password_confirm} || '');
    push @errors, 'Password must be at least 8 characters.' if length($params{password} || '') < 8;
    push @errors, 'Language must be ja or en.' unless ($params{language} || 'ja') =~ /\A(?:ja|en)\z/;
    return @errors;
}

sub initialize_site {
    for my $dir (
        'dat',
        'dat/articles',
        'dat/media',
        'dat/logs',
        'dat/security',
        'dat/sessions',
        'img',
        'img/uploads',
        'file',
    ) {
        make_path("$ROOT/$dir") unless -d "$ROOT/$dir";
    }

    my $language = $params{language} || 'ja';
    my $site_title = $params{site_title} || 'MARK6 Site';
    my $home_title = $language eq 'ja' ? 'ホーム' : 'Home';

    $store->write_json({
        version => 1,
        site => {
            title    => $site_title,
            base_url => '',
            language => $language,
        },
        features => {
            tags    => JSON::PP::true,
            newest  => JSON::PP::true,
            popular => JSON::PP::true,
            shop    => JSON::PP::false,
            ai      => JSON::PP::false,
        },
        display => {
            articles_per_page => 20,
            mini_articles     => 15,
        },
        shop => {
            title     => 'Shop',
            paypal_id => '',
        },
    }, 'dat', 'config.json');

    $store->write_json({
        title         => $home_title,
        body          => '',
        show_articles => JSON::PP::true,
        updated_at    => iso_now(),
    }, 'dat', 'home.json');

    $store->write_json({ version => 1, users => [] }, 'dat', 'users.json');
}

sub render_setup {
    my ($errors) = @_;
    my $error_html = '';
    if (@{$errors}) {
        my $items = join '', map { '<li>' . Mark6::CGI::escape_html($_) . '</li>' } @{$errors};
        $error_html = qq|<ul class="error">$items</ul>|;
    }

    my $site_title = Mark6::CGI::escape_html($params{site_title} || 'MARK6 Site');
    my $name = Mark6::CGI::escape_html($params{name} || '');
    my $language = $params{language} || 'ja';
    my $ja_selected = $language eq 'ja' ? 'selected' : '';
    my $en_selected = $language eq 'en' ? 'selected' : '';

    Mark6::CGI::print_html(<<"HTML");
<!doctype html>
<html lang="ja">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>MARK6 Setup</title>
  <link rel="stylesheet" href="../public/assets/css/mark6.css">
</head>
<body>
  <main class="site-main admin-login">
    <section class="article-detail">
      <h1>MARK6 Setup</h1>
      $error_html
      <form class="admin-form" method="post" action="setup.cgi">
        <label>Site title<br><input name="site_title" type="text" value="$site_title" required></label>
        <label>Language<br>
          <select name="language">
            <option value="ja" $ja_selected>Japanese</option>
            <option value="en" $en_selected>English</option>
          </select>
        </label>
        <label>Admin user ID<br><input name="name" type="text" value="$name" autocomplete="username" required></label>
        <label>Password<br><input name="password" type="password" autocomplete="new-password" required></label>
        <label>Password confirmation<br><input name="password_confirm" type="password" autocomplete="new-password" required></label>
        <button type="submit">Start MARK6</button>
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
        return $candidate if -d $candidate;
    }

    return "$FindBin::Bin/..";
}
