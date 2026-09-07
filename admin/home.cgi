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
use Mark6::Article;
use Mark6::Kiosk qw(config_for_lang item_type);
use Mark6::Lang;
use Mark6::Root;

my $ROOT = $ENV{MARK6_ROOT} || Mark6::Root::default_root(findbin => $FindBin::Bin, script => $0, marker => 'dat/users.json');
my $auth = Mark6::Auth->new(root => $ROOT);
my $store = Mark6::DataStore->new(root => $ROOT);
my $lang = Mark6::Lang->new(root => $ROOT);
my $config = $store->read_json('dat', 'config.json') || {};
my @home_langs = Mark6::Article::supported_langs($config);
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

    my $langs = home_langs($home);
    my $language_fields = home_language_fields($langs);
    my $kiosk_fields = home_kiosk_fields($home);
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
    $language_fields
    <label><input name="show_articles" type="checkbox" value="1" $show_articles_checked> $show_latest_label</label>
    $kiosk_fields
    <button type="submit">$save_label</button>
  </form>
  <script>
  (() => {
    for (const editor of document.querySelectorAll('.kiosk-editor')) {
      const tabs = Array.from(editor.querySelectorAll('[data-lang-tab]'));
      const panels = Array.from(editor.querySelectorAll('.lang-panel'));
      for (const tab of tabs) tab.addEventListener('click', () => {
        for (const item of tabs) item.classList.toggle('active', item === tab);
        for (const panel of panels) {
          const active = panel.id === tab.dataset.langTab;
          panel.hidden = !active;
          panel.classList.toggle('active', active);
        }
      });
      const updateRow = (row) => {
        const type = row.querySelector('[data-kiosk-type]')?.value || 'amazon';
        row.querySelector('[data-kiosk-amazon]').hidden = type !== 'amazon';
        row.querySelector('[data-kiosk-url]').hidden = type !== 'url';
      };
      for (const row of editor.querySelectorAll('[data-kiosk-row]')) {
        updateRow(row);
        row.querySelector('[data-kiosk-type]').addEventListener('change', () => updateRow(row));
      }
      for (const button of editor.querySelectorAll('[data-kiosk-add]')) button.addEventListener('click', () => {
        const panel = button.closest('.lang-panel');
        const row = Array.from(panel.querySelectorAll('[data-kiosk-row]')).find((item) => item.hidden);
        if (row) {
          row.hidden = false;
          updateRow(row);
        }
        if (!Array.from(panel.querySelectorAll('[data-kiosk-row]')).some((item) => item.hidden)) button.hidden = true;
      });
    }
  })();
  </script>
</section>
HTML
}

sub save_home {
    my $home = load_home();
    my $langs = collect_home_langs();
    my $default_lang = $config->{site}{default_lang} || $config->{site}{language} || $home_langs[0] || 'ja';
    my $default = $langs->{$default_lang} || {};

    $home->{title} = $default->{title} || 'Home';
    $home->{body} = $default->{body} || '';
    $home->{langs} = $langs;
    $home->{show_articles} = ($params{show_articles} || '') eq '1' ? JSON::PP::true : JSON::PP::false;
    $home->{kiosk} = collect_home_kiosk($home);
    $home->{updated_at} = iso_now();
    $store->write_json($home, 'dat', 'home.json');
}

sub home_langs {
    my ($home) = @_;
    my $default_lang = $config->{site}{default_lang} || $config->{site}{language} || $home_langs[0] || 'ja';
    my %langs = ref($home->{langs}) eq 'HASH' ? %{$home->{langs}} : ();

    if (!%langs) {
        $langs{$default_lang} = {
            title => $home->{title} || '',
            body  => $home->{body} || '',
        };
    }

    for my $code (@home_langs) {
        $langs{$code} ||= { title => '', body => '' };
        $langs{$code}{title} = '' unless defined $langs{$code}{title};
        $langs{$code}{body} = '' unless defined $langs{$code}{body};
    }

    return \%langs;
}

sub home_language_fields {
    my ($langs) = @_;
    my $title_label = h($lang->t('admin.home.title_label', 'Title'));
    my $body_label = h($lang->t('admin.home.body_html', 'Body HTML'));

    return join "\n", map {
        my $code = $_;
        my $entry = $langs->{$code} || {};
        my $name = h($lang->t("admin.lang.$code", $code));
        my $title = h($entry->{title} || '');
        my $body = h($entry->{body} || '');
        <<"HTML";
    <fieldset>
      <legend>$name</legend>
      <label>$title_label<br><input name="title_$code" type="text" value="$title"></label>
      <label>$body_label<br><textarea name="body_$code" rows="12">$body</textarea></label>
    </fieldset>
HTML
    } @home_langs;
}

sub collect_home_langs {
    my %langs;
    for my $code (@home_langs) {
        $langs{$code} = {
            title => $params{"title_$code"} || '',
            body  => $params{"body_$code"} || '',
        };
    }
    return \%langs;
}

sub home_kiosk_fields {
    my ($home) = @_;
    my $legend = h($lang->t('admin.home.kiosk', 'Home Kiosk'));
    my $enabled_label = h($lang->t('admin.home.kiosk_enabled', 'Show Kiosk on home'));
    my $mode_label = h($lang->t('admin.home.kiosk_mode', 'Kiosk source'));
    my $manual_label = h($lang->t('admin.home.kiosk_mode_manual', 'Manual home items'));
    my $auto_label = h($lang->t('admin.home.kiosk_mode_auto', 'Pick from article Kiosks'));
    my $label_text = h($lang->t('admin.article.kiosk_label', 'Label'));
    my $keyword_text = h($lang->t('admin.article.kiosk_keyword', 'Search keyword'));
    my $type_text = h($lang->t('admin.article.kiosk_type', 'Type'));
    my $amazon_text = h($lang->t('admin.article.kiosk_type_amazon', 'Amazon'));
    my $url_text = h($lang->t('admin.article.kiosk_type_url', 'URL'));
    my $url_label = h($lang->t('admin.article.kiosk_url', 'URL'));
    my $add_label = h($lang->t('admin.article.kiosk_add', 'Add item'));
    my $help = h($lang->t('admin.home.kiosk_help', 'Manual items are shown on home. Auto mode reuses public article Kiosk items.'));
    my $default_lang = $config->{site}{default_lang} || $config->{site}{language} || $home_langs[0] || 'ja';
    my (@tabs, @panels);

    for my $lang_code (@home_langs) {
        my $kiosk = config_for_lang($home->{kiosk}, $lang_code);
        my @items = ref($kiosk->{items}) eq 'ARRAY' ? @{$kiosk->{items}} : ();
        my $checked = $kiosk->{enabled} ? 'checked' : '';
        my $mode = ($kiosk->{mode} || 'manual') eq 'auto' ? 'auto' : 'manual';
        my $manual_selected = $mode eq 'manual' ? 'selected' : '';
        my $auto_selected = $mode eq 'auto' ? 'selected' : '';
        my $active = $lang_code eq $default_lang ? ' active' : '';
        my $hidden = $lang_code eq $default_lang ? '' : ' hidden';
        my $panel_id = "home-kiosk-panel-$lang_code";
        push @tabs, qq|      <button class="lang-tab$active" type="button" data-lang-tab="$panel_id">@{[uc $lang_code]}</button>|;
        my @rows;

        for my $index (0 .. 4) {
            my $item = ref($items[$index]) eq 'HASH' ? $items[$index] : {};
            my $number = $index + 1;
            my $label = h($item->{label} || '');
            my $keyword = h($item->{keyword} || '');
            my $url = h($item->{url} || '');
            my $type = item_type($item) || ($lang_code eq 'ja' ? 'amazon' : 'url');
            my $amazon_selected = $type eq 'amazon' ? 'selected' : '';
            my $url_selected = $type eq 'url' ? 'selected' : '';
            my $row_hidden = $index >= @items && $index > 0 ? ' hidden' : '';
            push @rows, <<"HTML";
        <div class="kiosk-admin-row" data-kiosk-row$row_hidden>
          <label>$label_text $number<br><input name="home_kiosk_label_${lang_code}_$number" type="text" value="$label"></label>
          <label>$type_text<br><select name="home_kiosk_type_${lang_code}_$number" data-kiosk-type><option value="amazon" $amazon_selected>$amazon_text</option><option value="url" $url_selected>$url_text</option></select></label>
          <label data-kiosk-amazon>$keyword_text<br><input name="home_kiosk_keyword_${lang_code}_$number" type="text" value="$keyword"></label>
          <label data-kiosk-url>$url_label<br><input name="home_kiosk_url_${lang_code}_$number" type="url" value="$url" placeholder="https://example.com/"></label>
        </div>
HTML
        }

        push @panels, <<"HTML";
      <section id="$panel_id" class="lang-panel$active"$hidden>
        <label><input name="home_kiosk_enabled_$lang_code" type="checkbox" value="1" $checked> $enabled_label</label>
        <label>$mode_label<br><select name="home_kiosk_mode_$lang_code"><option value="manual" $manual_selected>$manual_label</option><option value="auto" $auto_selected>$auto_label</option></select></label>
        <div class="kiosk-admin-grid" data-kiosk-rows>
@{[join '', @rows]}        </div>
        <button class="button secondary compact" type="button" data-kiosk-add>$add_label</button>
      </section>
HTML
    }

    return <<"HTML";
    <fieldset class="kiosk-editor">
      <legend>$legend</legend>
      <p class="meta">$help</p>
      <div class="lang-tabs" role="tablist">@{[join "\n", @tabs]}</div>
@{[join "\n", @panels]}
    </fieldset>
HTML
}

sub collect_home_kiosk {
    my ($home) = @_;
    my $existing = localized_kiosk_container($home->{kiosk});
    my $has_params = 0;
    for my $lang_code (@home_langs) {
        $has_params ||= exists $params{"home_kiosk_enabled_$lang_code"} || exists $params{"home_kiosk_mode_$lang_code"};
        for my $number (1 .. 5) {
            $has_params ||= exists $params{"home_kiosk_label_${lang_code}_$number"}
                || exists $params{"home_kiosk_keyword_${lang_code}_$number"}
                || exists $params{"home_kiosk_url_${lang_code}_$number"};
        }
    }
    return $existing if !$has_params && ref($home->{kiosk}) eq 'HASH';

    for my $lang_code (@home_langs) {
        my @items;
        for my $number (1 .. 5) {
            my $label = clean_text($params{"home_kiosk_label_${lang_code}_$number"} || '');
            my $type = ($params{"home_kiosk_type_${lang_code}_$number"} || '') eq 'url' ? 'url' : 'amazon';
            my $keyword = clean_text($params{"home_kiosk_keyword_${lang_code}_$number"} || '');
            my $url = clean_text($params{"home_kiosk_url_${lang_code}_$number"} || '');
            next if $label eq '' && $keyword eq '' && $url eq '';
            push @items, $type eq 'url'
                ? { label => $label ne '' ? $label : $url, type => 'url', url => $url }
                : { label => $label ne '' ? $label : $keyword, type => 'amazon', keyword => $keyword ne '' ? $keyword : $label };
        }
        my $mode = ($params{"home_kiosk_mode_$lang_code"} || 'manual') eq 'auto' ? 'auto' : 'manual';
        $existing->{$lang_code} = {
            enabled => ($params{"home_kiosk_enabled_$lang_code"} || '') eq '1' ? JSON::PP::true : JSON::PP::false,
            mode => $mode,
            items => \@items,
        };
    }

    return $existing;
}

sub localized_kiosk_container {
    my ($kiosk) = @_;
    return {} unless ref($kiosk) eq 'HASH';
    if (exists $kiosk->{enabled} || exists $kiosk->{items} || exists $kiosk->{mode}) {
        return { ja => { %{$kiosk} } };
    }
    return { %{$kiosk} };
}

sub clean_text {
    my ($value) = @_;
    $value = '' unless defined $value;
    $value =~ s/[\r\n\t]+/ /g;
    $value =~ s/^\s+|\s+$//g;
    return $value;
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
