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
    my $ai_provider = Mark6::CGI::escape_html($config->{ai}{provider} || 'openai');
    my $ai_model = Mark6::CGI::escape_html($config->{ai}{model} || 'gpt-5.2');
    my $ai_api_key_env = Mark6::CGI::escape_html($config->{ai}{api_key_env} || 'MARK6_OPENAI_API_KEY');
    my $ai_api_key_file = Mark6::CGI::escape_html($config->{ai}{api_key_file} || '');
    my $amazon_affiliate_tag = Mark6::CGI::escape_html($config->{kiosk}{affiliate_tag} || '');
    my $node_fields = node_settings_fields($config);
    my $free_space_fields = free_space_fields($config);

    my $tags_checked = checked($config->{features}{tags});
    my $newest_checked = checked($config->{features}{newest});
    my $popular_checked = checked($config->{features}{popular});
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
    my $ai_assist_label = h($lang->t('admin.settings.ai_assist', 'AI assist'));
    my $ai_label = h($lang->t('admin.settings.ai', 'AI'));
    my $ai_provider_label = h($lang->t('admin.settings.ai_provider', 'AI provider'));
    my $ai_model_label = h($lang->t('admin.settings.ai_model', 'AI model'));
    my $ai_api_key_env_label = h($lang->t('admin.settings.ai_api_key_env', 'API key environment variable'));
    my $ai_api_key_env_help = h($lang->t('admin.settings.ai_api_key_env_help', 'Enter the server environment variable name, not the API key itself.'));
    my $ai_api_key_file_label = h($lang->t('admin.settings.ai_api_key_file', 'API key file path'));
    my $ai_api_key_file_help = h($lang->t('admin.settings.ai_api_key_file_help', 'Optional. Keep this file outside the public web directory.'));
    my $openai_label = h($lang->t('admin.settings.ai_provider_openai', 'OpenAI'));
    my $kiosk_label = h($lang->t('admin.settings.kiosk', 'Kiosk'));
    my $nodes_label = h($lang->t('admin.settings.nodes', 'Sections'));
    my $nodes_help = h($lang->t('admin.settings.nodes_help', 'Sections shown in the public header. The ID is used in URLs.'));
    my $amazon_affiliate_tag_label = h($lang->t('admin.settings.amazon_affiliate_tag', 'Amazon Associate tag'));
    my $amazon_affiliate_tag_help = h($lang->t('admin.settings.amazon_affiliate_tag_help', 'Optional. Added to Amazon Kiosk search links as the tag parameter.'));
    my $free_space_label = h($lang->t('admin.settings.free_space', 'Free Space'));
    my $free_space_help = h($lang->t('admin.settings.free_space_help', 'Optional administrator-managed HTML for the three fixed public slots.'));
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
      <label><input name="feature_ai" type="checkbox" value="1" $ai_checked> $ai_assist_label</label>
    </fieldset>
    <fieldset>
      <legend>$nodes_label</legend>
      <p class="meta">$nodes_help</p>
      $node_fields
    </fieldset>
    <fieldset>
      <legend>$kiosk_label</legend>
      <label>$amazon_affiliate_tag_label<br><input name="amazon_affiliate_tag" type="text" value="$amazon_affiliate_tag"></label>
      <p class="meta">$amazon_affiliate_tag_help</p>
    </fieldset>
    <fieldset class="language-editor free-space-editor">
      <legend>$free_space_label</legend>
      <p class="meta">$free_space_help</p>
      $free_space_fields
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
      <p class="meta">$ai_api_key_env_help</p>
      <label>$ai_api_key_file_label<br><input name="ai_api_key_file" type="text" value="$ai_api_key_file" placeholder="/home/example/.mark6_openai_key"></label>
      <p class="meta">$ai_api_key_file_help</p>
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
    $config->{kiosk} ||= {};
    $config->{ai} ||= {};
    $config->{free_space} ||= {};
    $config->{nodes} = collect_nodes();

    $config->{site}{title} = $params{site_title} || 'MARK6 Site';
    $config->{site}{base_url} = $params{base_url} || '';
    $config->{site}{language} = ($params{language} || 'ja') eq 'en' ? 'en' : 'ja';

    $config->{display}{articles_per_page} = bounded_number($params{articles_per_page}, 20, 1, 100);
    $config->{display}{mini_articles} = bounded_number($params{mini_articles}, 15, 1, 100);

    $config->{features}{tags} = bool_param('feature_tags');
    $config->{features}{newest} = bool_param('feature_newest');
    $config->{features}{popular} = bool_param('feature_popular');
    $config->{features}{ai} = bool_param('feature_ai');
    delete $config->{features}{shop};

    delete $config->{shop};
    $config->{kiosk}{provider} = 'amazon';
    $config->{kiosk}{affiliate_tag} = clean_affiliate_tag($params{amazon_affiliate_tag} || '');
    $config->{ai}{provider} = 'openai';
    $config->{ai}{model} = clean_text($params{ai_model} || 'gpt-5.2');
    $config->{ai}{api_key_env} = clean_env_name($params{ai_api_key_env} || 'MARK6_OPENAI_API_KEY');
    $config->{ai}{api_key_file} = clean_path($params{ai_api_key_file} || '');
    $config->{free_space} = collect_free_space();

    $store->write_json($config, 'dat', 'config.json');
}

sub free_space_fields {
    my ($config) = @_;
    my @langs = qw(ja en);
    my @slots = qw(home_bottom article_end after_kiosk);
    my @tabs;
    my @panels;
    my $all = ref($config->{free_space}) eq 'HASH' ? $config->{free_space} : {};

    for my $index (0 .. $#langs) {
        my $code = $langs[$index];
        my $active = $index == 0 ? ' active' : '';
        my $hidden = $index == 0 ? '' : ' hidden';
        my $panel_id = "free-space-panel-$code";
        push @tabs, qq|<button class="lang-tab$active" type="button" data-lang-tab="$panel_id">@{[uc $code]}</button>|;
        my @fields;
        for my $slot (@slots) {
            my $localized = ref($all->{$slot}) eq 'HASH' ? $all->{$slot} : {};
            my $entry = ref($localized->{$code}) eq 'HASH' ? $localized->{$code} : {};
            my $enabled = checked($entry->{enabled});
            my $html = h($entry->{html} || '');
            my $slot_label = h($lang->t("admin.settings.free_space_$slot", $slot));
            my $show_label = h($lang->t('admin.settings.free_space_enabled', 'Enable this slot'));
            push @fields, <<"HTML";
        <div class="free-space-field">
          <h3>$slot_label</h3>
          <label><input name="free_space_${slot}_${code}_enabled" type="checkbox" value="1" $enabled> $show_label</label>
          <textarea name="free_space_${slot}_${code}_html" rows="6" spellcheck="false">$html</textarea>
        </div>
HTML
        }
        push @panels, qq|<section id="$panel_id" class="lang-panel$active"$hidden>| . join('', @fields) . '</section>';
    }

    return '<div class="lang-tabs" role="tablist">' . join('', @tabs) . '</div>' . join('', @panels) . free_space_script();
}

sub free_space_script {
    return <<'HTML';
<script>
(() => {
  for (const group of document.querySelectorAll('.free-space-editor')) {
    const tabs = Array.from(group.querySelectorAll('[data-lang-tab]'));
    const panels = Array.from(group.querySelectorAll('.lang-panel'));
    tabs.forEach((tab) => tab.addEventListener('click', () => {
      tabs.forEach((item) => item.classList.toggle('active', item === tab));
      panels.forEach((panel) => {
        const active = panel.id === tab.dataset.langTab;
        panel.hidden = !active;
        panel.classList.toggle('active', active);
      });
    }));
  }
})();
</script>
HTML
}

sub collect_free_space {
    my %free_space;
    for my $slot (qw(home_bottom article_end after_kiosk)) {
        for my $code (qw(ja en)) {
            $free_space{$slot}{$code} = {
                enabled => bool_param("free_space_${slot}_${code}_enabled"),
                html => $params{"free_space_${slot}_${code}_html"} || '',
            };
        }
    }
    return \%free_space;
}

sub load_config {
    return $store->read_json('dat', 'config.json') || {
        version => 1,
        site => { title => 'MARK6 Site', base_url => '', language => 'ja' },
        features => { tags => JSON::PP::true, newest => JSON::PP::true, popular => JSON::PP::true, ai => JSON::PP::false },
        display => { articles_per_page => 20, mini_articles => 15 },
        content_checker => {
            profile => 'default',
            text_limits => { default => { description_min_chars => 100, body_min_chars => 500 } },
            slug_check => { enabled => JSON::PP::true, allow_id_slug => JSON::PP::false },
        },
        nodes => {},
        kiosk => { provider => 'amazon', affiliate_tag => '' },
        free_space => {},
        ai => { provider => 'openai', model => 'gpt-5.2', api_key_env => 'MARK6_OPENAI_API_KEY', api_key_file => '' },
    };
}

sub node_settings_fields {
    my ($config) = @_;
    my $nodes = ref($config->{nodes}) eq 'HASH' ? $config->{nodes} : {};
    my @ids = sort keys %{$nodes};
    my $default_node = $config->{site}{node} || 'articles';
    unshift @ids, $default_node if $default_node ne '' && !grep { $_ eq $default_node } @ids;
    @ids = @ids[0 .. 4] if @ids > 5;
    push @ids, ('') x (5 - @ids) if @ids < 5;

    my $id_label = h($lang->t('admin.settings.node_id', 'Section ID'));
    my $ja_label = h($lang->t('admin.settings.node_label_ja', 'Japanese label'));
    my $en_label = h($lang->t('admin.settings.node_label_en', 'English label'));
    my $nav_label = h($lang->t('admin.settings.node_nav', 'Show in header'));
    my @rows;

    for my $index (0 .. $#ids) {
        my $number = $index + 1;
        my $id = $ids[$index];
        my $node = ref($nodes->{$id}) eq 'HASH' ? $nodes->{$id} : {};
        my $labels = ref($node->{labels}) eq 'HASH' ? $node->{labels} : {};
        my $safe_id = h($id);
        my $label_ja = h($labels->{ja} || ($id eq $default_node ? $id : ''));
        my $label_en = h($labels->{en} || ($id eq $default_node ? $id : ''));
        my $checked = checked(!exists($node->{nav}) || $node->{nav});
        push @rows, <<"HTML";
      <div class="node-settings-row">
        <label>$id_label $number<br><input name="node_id_$number" type="text" value="$safe_id"></label>
        <label>$ja_label<br><input name="node_label_ja_$number" type="text" value="$label_ja"></label>
        <label>$en_label<br><input name="node_label_en_$number" type="text" value="$label_en"></label>
        <label class="inline-check"><input name="node_nav_$number" type="checkbox" value="1" $checked> $nav_label</label>
      </div>
HTML
    }

    return '<div class="node-settings-grid">' . join('', @rows) . '</div>';
}

sub collect_nodes {
    my %nodes;
    for my $number (1 .. 5) {
        my $id = safe_segment($params{"node_id_$number"} || '');
        next if $id eq '';
        my $label_ja = clean_text($params{"node_label_ja_$number"} || '');
        my $label_en = clean_text($params{"node_label_en_$number"} || '');
        $nodes{$id} = {
            nav => bool_param("node_nav_$number"),
            labels => {
                ja => $label_ja ne '' ? $label_ja : $id,
                en => $label_en ne '' ? $label_en : $id,
            },
        };
    }
    return \%nodes;
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

sub clean_affiliate_tag {
    my ($value) = @_;
    $value = clean_text($value);
    $value =~ s/[^0-9A-Za-z_-]//g;
    return $value;
}

sub safe_segment {
    my ($value) = @_;
    $value = clean_text($value);
    return $value =~ /\A[0-9A-Za-z_-]+\z/ ? $value : '';
}

sub clean_path {
    my ($value) = @_;
    $value = clean_text($value);
    return '' if $value =~ /\0/;
    return $value;
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
