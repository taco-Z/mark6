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

if (($ENV{REQUEST_METHOD} || 'GET') eq 'POST') {
    unless ($auth->verify_csrf($session, $params{csrf_token} || '')) {
        render_page('CSRF Error', '<p class="error">Invalid form token.</p>');
        exit;
    }

    save_settings();
    Mark6::CGI::redirect('settings.cgi?saved=1');
    exit;
}

render_settings();

sub render_settings {
    my $config = load_config();
    my $csrf = Mark6::CGI::escape_html($session->{csrf_token} || '');
    my $saved = ($params{saved} || '') eq '1' ? '<p class="notice">Settings saved.</p>' : '';

    my $site_title = Mark6::CGI::escape_html($config->{site}{title} || '');
    my $base_url = Mark6::CGI::escape_html($config->{site}{base_url} || '');
    my $language = $config->{site}{language} || 'ja';
    my $ja_selected = $language eq 'ja' ? 'selected' : '';
    my $en_selected = $language eq 'en' ? 'selected' : '';

    my $articles_per_page = Mark6::CGI::escape_html($config->{display}{articles_per_page} || 20);
    my $mini_articles = Mark6::CGI::escape_html($config->{display}{mini_articles} || 15);
    my $shop_title = Mark6::CGI::escape_html($config->{shop}{title} || 'Shop');
    my $paypal_id = Mark6::CGI::escape_html($config->{shop}{paypal_id} || '');

    my $tags_checked = checked($config->{features}{tags});
    my $newest_checked = checked($config->{features}{newest});
    my $popular_checked = checked($config->{features}{popular});
    my $shop_checked = checked($config->{features}{shop});
    my $ai_checked = checked($config->{features}{ai});

    render_page('Settings', <<"HTML");
<section class="article-detail">
  <a class="back-link" href="index.cgi">Dashboard</a>
  <h1>Settings</h1>
  $saved
  <form class="admin-form" method="post" action="settings.cgi">
    <input type="hidden" name="csrf_token" value="$csrf">
    <fieldset>
      <legend>Site</legend>
      <label>Site title<br><input name="site_title" type="text" value="$site_title" required></label>
      <label>Base URL<br><input name="base_url" type="url" value="$base_url"></label>
      <label>Language<br>
        <select name="language">
          <option value="ja" $ja_selected>Japanese</option>
          <option value="en" $en_selected>English</option>
        </select>
      </label>
    </fieldset>
    <fieldset>
      <legend>Display</legend>
      <label>Articles per page<br><input name="articles_per_page" type="number" min="1" max="100" value="$articles_per_page"></label>
      <label>Mini articles<br><input name="mini_articles" type="number" min="1" max="100" value="$mini_articles"></label>
    </fieldset>
    <fieldset>
      <legend>Features</legend>
      <label><input name="feature_tags" type="checkbox" value="1" $tags_checked> Tags</label>
      <label><input name="feature_newest" type="checkbox" value="1" $newest_checked> Newest list</label>
      <label><input name="feature_popular" type="checkbox" value="1" $popular_checked> Popular list</label>
      <label><input name="feature_shop" type="checkbox" value="1" $shop_checked> Shop</label>
      <label><input name="feature_ai" type="checkbox" value="1" $ai_checked> AI assist</label>
    </fieldset>
    <fieldset>
      <legend>Shop</legend>
      <label>Shop title<br><input name="shop_title" type="text" value="$shop_title"></label>
      <label>PayPal ID<br><input name="paypal_id" type="text" value="$paypal_id"></label>
    </fieldset>
    <button type="submit">Save Settings</button>
  </form>
</section>
HTML
}

sub save_settings {
    my $config = load_config();

    $config->{version} ||= 1;
    $config->{site} ||= {};
    $config->{features} ||= {};
    $config->{display} ||= {};
    $config->{shop} ||= {};

    $config->{site}{title} = $params{site_title} || 'MARK6 Site';
    $config->{site}{base_url} = $params{base_url} || '';
    $config->{site}{language} = ($params{language} || 'ja') eq 'en' ? 'en' : 'ja';

    $config->{display}{articles_per_page} = bounded_number($params{articles_per_page}, 20, 1, 100);
    $config->{display}{mini_articles} = bounded_number($params{mini_articles}, 15, 1, 100);

    $config->{features}{tags} = bool_param('feature_tags');
    $config->{features}{newest} = bool_param('feature_newest');
    $config->{features}{popular} = bool_param('feature_popular');
    $config->{features}{shop} = bool_param('feature_shop');
    $config->{features}{ai} = bool_param('feature_ai');

    $config->{shop}{title} = $params{shop_title} || 'Shop';
    $config->{shop}{paypal_id} = $params{paypal_id} || '';

    $store->write_json($config, 'dat', 'config.json');
}

sub load_config {
    return $store->read_json('dat', 'config.json') || {
        version => 1,
        site => { title => 'MARK6 Site', base_url => '', language => 'ja' },
        features => { tags => JSON::PP::true, newest => JSON::PP::true, popular => JSON::PP::true, shop => JSON::PP::false, ai => JSON::PP::false },
        display => { articles_per_page => 20, mini_articles => 15 },
        shop => { title => 'Shop', paypal_id => '' },
    };
}

sub checked {
    return $_[0] ? 'checked' : '';
}

sub bool_param {
    my ($name) = @_;
    return ($params{$name} || '') eq '1' ? JSON::PP::true : JSON::PP::false;
}

sub bounded_number {
    my ($value, $default, $min, $max) = @_;
    return $default unless defined $value && $value =~ /\A\d+\z/;
    $value = 0 + $value;
    return $min if $value < $min;
    return $max if $value > $max;
    return $value;
}

sub render_page {
    my ($title, $content) = @_;
    Mark6::Admin::render_page(
        title   => $title,
        active  => 'settings',
        content => $content,
    );
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
