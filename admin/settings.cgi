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

    save_settings();
    Mark6::CGI::redirect('settings.cgi?saved=1');
    exit;
}

render_settings();

sub render_settings {
    my $config = load_config();
    my $csrf = Mark6::CGI::escape_html($session->{csrf_token} || '');
    my $saved = ($params{saved} || '') eq '1' ? '<p class="notice">' . h($lang->t('admin.settings.saved', 'Settings saved.')) . '</p>' : '';

    my $site_title = Mark6::CGI::escape_html($config->{site}{title} || '');
    my $base_url = Mark6::CGI::escape_html($config->{site}{base_url} || '');
    my $language = $config->{site}{language} || 'ja';
    my $ja_selected = $language eq 'ja' ? 'selected' : '';
    my $en_selected = $language eq 'en' ? 'selected' : '';

    my $articles_per_page = Mark6::CGI::escape_html($config->{display}{articles_per_page} || 20);
    my $mini_articles = Mark6::CGI::escape_html($config->{display}{mini_articles} || 15);
    my $shop_title = Mark6::CGI::escape_html($config->{shop}{title} || 'Shop');
    my $paypal_id = Mark6::CGI::escape_html($config->{shop}{paypal_id} || '');
    my $ai_provider = Mark6::CGI::escape_html($config->{ai}{provider} || 'openai');
    my $ai_model = Mark6::CGI::escape_html($config->{ai}{model} || 'gpt-5.2');
    my $ai_api_key_env = Mark6::CGI::escape_html($config->{ai}{api_key_env} || 'MARK6_OPENAI_API_KEY');

    my $tags_checked = checked($config->{features}{tags});
    my $newest_checked = checked($config->{features}{newest});
    my $popular_checked = checked($config->{features}{popular});
    my $shop_checked = checked($config->{features}{shop});
    my $ai_checked = checked($config->{features}{ai});
    my $page_title = h($lang->t('admin.common.settings', 'Settings'));
    my $dashboard_label = h($lang->t('admin.common.dashboard', 'Dashboard'));
    my $site_label = h($lang->t('admin.settings.site', 'Site'));
    my $site_title_label = h($lang->t('admin.settings.site_title', 'Site title'));
    my $base_url_label = h($lang->t('admin.settings.base_url', 'Base URL'));
    my $language_label = h($lang->t('admin.settings.language', 'Language'));
    my $ja_label = h($lang->t('admin.lang.ja', 'Japanese'));
    my $en_label = h($lang->t('admin.lang.en', 'English'));
    my $display_label = h($lang->t('admin.settings.display', 'Display'));
    my $articles_per_page_label = h($lang->t('admin.settings.articles_per_page', 'Articles per page'));
    my $mini_articles_label = h($lang->t('admin.settings.mini_articles', 'Mini articles'));
    my $features_label = h($lang->t('admin.settings.features', 'Features'));
    my $tags_label = h($lang->t('admin.settings.tags', 'Tags'));
    my $newest_list_label = h($lang->t('admin.settings.newest_list', 'Newest list'));
    my $popular_list_label = h($lang->t('admin.settings.popular_list', 'Popular list'));
    my $shop_label = h($lang->t('admin.settings.shop', 'Shop'));
    my $ai_assist_label = h($lang->t('admin.settings.ai_assist', 'AI assist'));
    my $shop_title_label = h($lang->t('admin.settings.shop_title', 'Shop title'));
    my $paypal_id_label = h($lang->t('admin.settings.paypal_id', 'PayPal ID'));
    my $ai_label = h($lang->t('admin.settings.ai', 'AI'));
    my $ai_provider_label = h($lang->t('admin.settings.ai_provider', 'AI provider'));
    my $ai_model_label = h($lang->t('admin.settings.ai_model', 'AI model'));
    my $ai_api_key_env_label = h($lang->t('admin.settings.ai_api_key_env', 'API key environment variable'));
    my $openai_label = h($lang->t('admin.settings.ai_provider_openai', 'OpenAI'));
    my $save_label = h($lang->t('admin.settings.save', 'Save Settings'));

    render_page($lang->t('admin.common.settings', 'Settings'), <<"HTML");
<section class="article-detail">
  <a class="back-link" href="index.cgi">$dashboard_label</a>
  <h1>$page_title</h1>
  $saved
  <form class="admin-form" method="post" action="settings.cgi">
    <input type="hidden" name="csrf_token" value="$csrf">
    <fieldset>
      <legend>$site_label</legend>
      <label>$site_title_label<br><input name="site_title" type="text" value="$site_title" required></label>
      <label>$base_url_label<br><input name="base_url" type="url" value="$base_url"></label>
      <label>$language_label<br>
        <select name="language">
          <option value="ja" $ja_selected>$ja_label</option>
          <option value="en" $en_selected>$en_label</option>
        </select>
      </label>
    </fieldset>
    <fieldset>
      <legend>$display_label</legend>
      <label>$articles_per_page_label<br><input name="articles_per_page" type="number" min="1" max="100" value="$articles_per_page"></label>
      <label>$mini_articles_label<br><input name="mini_articles" type="number" min="1" max="100" value="$mini_articles"></label>
    </fieldset>
    <fieldset>
      <legend>$features_label</legend>
      <label><input name="feature_tags" type="checkbox" value="1" $tags_checked> $tags_label</label>
      <label><input name="feature_newest" type="checkbox" value="1" $newest_checked> $newest_list_label</label>
      <label><input name="feature_popular" type="checkbox" value="1" $popular_checked> $popular_list_label</label>
      <label><input name="feature_shop" type="checkbox" value="1" $shop_checked> $shop_label</label>
      <label><input name="feature_ai" type="checkbox" value="1" $ai_checked> $ai_assist_label</label>
    </fieldset>
    <fieldset>
      <legend>$shop_label</legend>
      <label>$shop_title_label<br><input name="shop_title" type="text" value="$shop_title"></label>
      <label>$paypal_id_label<br><input name="paypal_id" type="text" value="$paypal_id"></label>
    </fieldset>
    <fieldset>
      <legend>$ai_label</legend>
      <label>$ai_provider_label<br>
        <select name="ai_provider">
          <option value="openai" selected>$openai_label</option>
        </select>
      </label>
      <label>$ai_model_label<br><input name="ai_model" type="text" value="$ai_model"></label>
      <label>$ai_api_key_env_label<br><input name="ai_api_key_env" type="text" value="$ai_api_key_env"></label>
    </fieldset>
    <button type="submit">$save_label</button>
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
    $config->{ai} ||= {};

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
    $config->{ai}{provider} = 'openai';
    $config->{ai}{model} = clean_text($params{ai_model} || 'gpt-5.2');
    $config->{ai}{api_key_env} = clean_env_name($params{ai_api_key_env} || 'MARK6_OPENAI_API_KEY');

    $store->write_json($config, 'dat', 'config.json');
}

sub load_config {
    return $store->read_json('dat', 'config.json') || {
        version => 1,
        site => { title => 'MARK6 Site', base_url => '', language => 'ja' },
        features => { tags => JSON::PP::true, newest => JSON::PP::true, popular => JSON::PP::true, shop => JSON::PP::false, ai => JSON::PP::false },
        display => { articles_per_page => 20, mini_articles => 15 },
        shop => { title => 'Shop', paypal_id => '' },
        ai => { provider => 'openai', model => 'gpt-5.2', api_key_env => 'MARK6_OPENAI_API_KEY' },
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

sub clean_text {
    my ($value) = @_;
    $value = '' unless defined $value;
    $value =~ s/^\s+|\s+$//g;
    return $value;
}

sub clean_env_name {
    my ($value) = @_;
    $value = clean_text($value);
    return $value =~ /\A[A-Za-z_][A-Za-z0-9_]*\z/ ? $value : 'MARK6_OPENAI_API_KEY';
}

sub render_page {
    my ($title, $content) = @_;
    Mark6::Admin::render_page(
        title   => $title,
        active  => 'settings',
        root    => $ROOT,
        lang    => $lang,
        content => $content,
    );
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
