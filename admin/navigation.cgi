#!/usr/bin/env perl

use strict;
use warnings;
use utf8;
use FindBin;
use JSON::PP ();

BEGIN {
    unshift @INC, "$FindBin::Bin/../lib" if -d "$FindBin::Bin/../lib";
}

use Mark6::Article;
use Mark6::Auth;
use Mark6::Admin;
use Mark6::CGI qw();
use Mark6::DataStore;
use Mark6::Lang;
use Mark6::Root;

my $ROOT = $ENV{MARK6_ROOT} || Mark6::Root::default_root(findbin => $FindBin::Bin, script => $0, marker => 'dat/users.json');
my $auth = Mark6::Auth->new(root => $ROOT);
my $store = Mark6::DataStore->new(root => $ROOT);
my $config = $store->read_json('dat', 'config.json') || {};
my $lang = Mark6::Lang->new(root => $ROOT);
my @langs = Mark6::Article::supported_langs($config);
my %params = Mark6::CGI::request_params();
my %cookies = Mark6::CGI::cookies();
my $session = $auth->read_session($cookies{mark6_session} || '');

unless ($session && $auth->find_user_by_id($session->{user_id})) {
    Mark6::CGI::redirect('login.cgi');
    exit;
}

if (($ENV{REQUEST_METHOD} || 'GET') eq 'POST') {
    unless ($auth->verify_csrf($session, $params{csrf_token} || '')) {
        render('<p class="error">' . h($lang->t('admin.common.invalid_form_token', 'Invalid form token.')) . '</p>');
        exit;
    }
    my $error = eval { save_navigation(); 1 } ? '' : ($@ || 'Unable to save navigation');
    if ($error ne '') {
        chomp $error;
        render('<p class="error">' . h($error) . '</p>' . navigation_form());
        exit;
    }
    Mark6::CGI::redirect('navigation.cgi?saved=1');
    exit;
}

my $saved = ($params{saved} || '') eq '1'
    ? '<p class="notice">' . h($lang->t('admin.navigation.saved', 'Navigation saved.')) . '</p>'
    : '';
render($saved . navigation_form());

sub navigation_form {
    my $csrf = h($session->{csrf_token} || '');
    my $title = h($lang->t('admin.navigation.title', 'Navigation'));
    my $help = h($lang->t('admin.navigation.help', 'Manage simple header and footer links. Internal paths automatically use the site base URL.'));
    my $save = h($lang->t('admin.navigation.save', 'Save Navigation'));
    my $header = navigation_area('header', $lang->t('admin.navigation.header', 'Header Navigation'));
    my $footer = navigation_area('footer', $lang->t('admin.navigation.footer', 'Footer Navigation'));

    return <<"HTML";
<section class="article-detail">
  <h1>$title</h1>
  <p class="meta">$help</p>
  <form class="admin-form navigation-editor" method="post" action="navigation.cgi">
    <input type="hidden" name="csrf_token" value="$csrf">
    $header
    $footer
    <button type="submit">$save</button>
  </form>
  <style>.navigation-row[hidden] { display: none !important; }</style>
  <script>
  (() => {
    const fields = ['input[type="checkbox"]', 'input[name*="_label_"]', 'input[name*="_url_"]'];
    const values = (row) => fields.map((selector) => {
      const input = row.querySelector(selector);
      return input && input.type === 'checkbox' ? input.checked : (input?.value || '');
    });
    const setValues = (row, data) => fields.forEach((selector, index) => {
      const input = row.querySelector(selector);
      if (!input) return;
      if (input.type === 'checkbox') input.checked = Boolean(data[index]);
      else input.value = data[index] || '';
    });
    for (const editor of document.querySelectorAll('[data-navigation-list]')) {
      const rows = Array.from(editor.querySelectorAll('[data-navigation-row]'));
      editor.addEventListener('click', (event) => {
        const button = event.target.closest('button');
        if (!button) return;
        const row = button.closest('[data-navigation-row]');
        if (button.dataset.navAdd !== undefined) {
          const hidden = rows.find((item) => item.hidden);
          if (hidden) { hidden.hidden = false; hidden.querySelector('input[type="text"]')?.focus(); }
          button.hidden = !rows.some((item) => item.hidden);
          return;
        }
        if (!row) return;
        if (button.dataset.navRemove !== undefined) {
          setValues(row, [false, '', '']);
          row.hidden = true;
          editor.querySelector('[data-nav-add]').hidden = false;
          return;
        }
        const direction = button.dataset.navMove;
        if (!direction) return;
        const visible = rows.filter((item) => !item.hidden);
        const index = visible.indexOf(row);
        const other = direction === 'up' ? visible[index - 1] : visible[index + 1];
        if (!other) return;
        const currentValues = values(row);
        setValues(row, values(other));
        setValues(other, currentValues);
      });
    }
    for (const group of document.querySelectorAll('.language-editor')) {
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
</section>
HTML
}

sub navigation_area {
    my ($area, $legend) = @_;
    my (@tabs, @panels);
    my $navigation = ref($config->{navigation}) eq 'HASH' ? $config->{navigation} : {};
    my $area_config = ref($navigation->{$area}) eq 'HASH' ? $navigation->{$area} : {};

    my $system = ref($area_config->{system}) eq 'HASH' ? $area_config->{system} : {};
    my $system_label = h($lang->t('admin.navigation.system', 'Automatic links'));
    my $system_help = h($lang->t('admin.navigation.system_help', 'These links are generated from the current site structure and appear before manual links.'));
    my $show_text = h($lang->t('admin.navigation.enabled', 'Show'));
    my $system_fields = '';
    if ($area eq 'header') {
        my @system_items = (
            ['home', $lang->t('admin.navigation.system_home', 'Home')],
            ['articles', $lang->t('admin.navigation.system_articles', 'Articles')],
            ['sections', $lang->t('admin.navigation.system_sections', 'Sections')],
        );
        for my $item (@system_items) {
            my ($key, $label) = @{$item};
            my $checked = !exists($system->{$key}) || $system->{$key} ? 'checked' : '';
            $system_fields .= qq|<label class="inline-check"><input name="${area}_system_${key}" type="checkbox" value="1" $checked> @{[h($label)]}</label> |;
        }
        $system_fields = qq|<fieldset class="navigation-system"><legend>$system_label</legend><p class="meta">$system_help</p>$system_fields</fieldset>|;
    }

    for my $index (0 .. $#langs) {
        my $code = $langs[$index];
        my @items = ref($area_config->{$code}) eq 'ARRAY'
            ? grep {
                ref($_) eq 'HASH'
                    && (clean_text($_->{label} || '') ne '' || clean_text($_->{url} || '') ne '')
            } @{$area_config->{$code}}
            : ();
        my $active = $index == 0 ? ' active' : '';
        my $hidden = $index == 0 ? '' : ' hidden';
        my $panel_id = "navigation-$area-$code";
        my $panel_system_fields = $index == 0 ? $system_fields : '';
        push @tabs, qq|<button class="lang-tab$active" type="button" data-lang-tab="$panel_id">@{[uc $code]}</button>|;
        my @rows;
        for my $row_index (0 .. 9) {
            my $number = $row_index + 1;
            my $item = ref($items[$row_index]) eq 'HASH' ? $items[$row_index] : {};
            my $row_hidden = $row_index >= @items && $row_index > 0 ? ' hidden' : '';
            my $checked = !exists($item->{enabled}) || $item->{enabled} ? 'checked' : '';
            my $label = h($item->{label} || '');
            my $url = h($item->{url} || '');
            my $label_text = h($lang->t('admin.navigation.label', 'Label'));
            my $url_text = h($lang->t('admin.navigation.url', 'URL'));
            my $show_text = h($lang->t('admin.navigation.enabled', 'Show'));
            my $up = h($lang->t('admin.navigation.up', 'Up'));
            my $down = h($lang->t('admin.navigation.down', 'Down'));
            my $remove = h($lang->t('admin.navigation.remove', 'Remove'));
            push @rows, <<"HTML";
        <div class="navigation-row" data-navigation-row$row_hidden>
          <label class="inline-check"><input name="${area}_${code}_enabled_$number" type="checkbox" value="1" $checked> $show_text</label>
          <label>$label_text<br><input name="${area}_${code}_label_$number" type="text" value="$label"></label>
          <label>$url_text<br><input name="${area}_${code}_url_$number" type="text" value="$url" placeholder="/about/ or https://example.com/"></label>
          <div class="navigation-row-actions">
            <button class="button secondary compact" type="button" data-nav-move="up">$up</button>
            <button class="button secondary compact" type="button" data-nav-move="down">$down</button>
            <button class="button secondary compact" type="button" data-nav-remove>$remove</button>
          </div>
        </div>
HTML
        }
        my $add = h($lang->t('admin.navigation.add', 'Add link'));
        push @panels, <<"HTML";
      <section id="$panel_id" class="lang-panel$active"$hidden>
        $panel_system_fields
        <div class="navigation-list" data-navigation-list>
@{[join '', @rows]}
          <button class="button secondary compact" type="button" data-nav-add>$add</button>
        </div>
      </section>
HTML
    }

    return <<"HTML";
    <fieldset class="language-editor">
      <legend>@{[h($legend)]}</legend>
      <div class="lang-tabs" role="tablist">@{[join '', @tabs]}</div>
@{[join '', @panels]}
    </fieldset>
HTML
}

sub save_navigation {
    $config->{navigation} ||= {};
    for my $area (qw(header footer)) {
        $config->{navigation}{$area} ||= {};
        if ($area eq 'header') {
            $config->{navigation}{$area}{system} = {
                home => ($params{header_system_home} || '') eq '1' ? JSON::PP::true : JSON::PP::false,
                articles => ($params{header_system_articles} || '') eq '1' ? JSON::PP::true : JSON::PP::false,
                sections => ($params{header_system_sections} || '') eq '1' ? JSON::PP::true : JSON::PP::false,
            };
        }
        for my $code (@langs) {
            my @items;
            for my $number (1 .. 10) {
                my $label = clean_text($params{"${area}_${code}_label_$number"} || '');
                my $url = clean_url($params{"${area}_${code}_url_$number"} || '');
                next if $label eq '' && $url eq '';
                die "Navigation label and URL are required" if $label eq '' || $url eq '';
                push @items, {
                    label => $label,
                    url => $url,
                    enabled => ($params{"${area}_${code}_enabled_$number"} || '') eq '1' ? JSON::PP::true : JSON::PP::false,
                };
            }
            $config->{navigation}{$area}{$code} = \@items;
        }
    }
    $store->write_json($config, 'dat', 'config.json');
}

sub clean_url {
    my ($value) = @_;
    $value = clean_text($value);
    return '' if $value eq '';
    return $value if $value =~ m{\Ahttps?://[^\s<>"']+\z}i;
    return $value if $value =~ m{\A/[0-9A-Za-z_./?&=%#~-]*\z} && $value !~ /\.\./;
    die "Navigation URL must be an internal path or an http(s) URL";
}

sub clean_text {
    my ($value) = @_;
    $value = '' unless defined $value;
    $value =~ s/^\s+|\s+$//g;
    return $value;
}

sub render {
    my ($content) = @_;
    Mark6::Admin::render_page(
        title => $lang->t('admin.navigation.title', 'Navigation'),
        active => 'navigation', root => $ROOT, lang => $lang, content => $content,
    );
}

sub h { return Mark6::CGI::escape_html(defined $_[0] ? $_[0] : ''); }
