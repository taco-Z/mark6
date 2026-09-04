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
use Mark6::AI;
use Mark6::Article;
use Mark6::CGI qw();
use Mark6::DataStore;
use Mark6::Lang;
use Mark6::Root;

my $ROOT = $ENV{MARK6_ROOT} || Mark6::Root::default_root(findbin => $FindBin::Bin, script => $0, marker => 'dat/users.json');
my $auth = Mark6::Auth->new(root => $ROOT);
my $store = Mark6::DataStore->new(root => $ROOT);
my $config = $store->read_json('dat', 'config.json') || {};
my $lang = Mark6::Lang->new(root => $ROOT);
my @article_langs = Mark6::Article::supported_langs($config);
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

my $command = $params{command} || 'list';

if (($ENV{REQUEST_METHOD} || 'GET') eq 'POST') {
    unless ($auth->verify_csrf($session, $params{csrf_token} || '')) {
        render_page($lang->t('admin.common.csrf_error', 'CSRF Error'), '<p class="error">' . h($lang->t('admin.common.invalid_form_token', 'Invalid form token.')) . '</p>');
        exit;
    }

    if ($command eq 'save') {
        my $error = run_admin_action(sub { save_article() });
        if ($error) {
            render_page($lang->t('admin.article.save_error', 'Save Error'), qq|<p class="error">$error</p>|);
            exit;
        }
        Mark6::CGI::redirect('articles.cgi');
        exit;
    }

    if ($command eq 'ai_run_selected') {
        my $article_id = '';
        my $error = run_admin_action(sub {
            $article_id = save_article();
            perform_ai_batch($article_id);
        });
        if ($error) {
            render_form(load_article($article_id || $params{id} || '') || blank_article(), $lang->t('admin.article.edit', 'Edit Article'), $error);
            exit;
        }
        Mark6::CGI::redirect('articles.cgi?command=edit&id=' . Mark6::CGI::url_encode($article_id) . '&ai=selected_done#ai-assist');
        exit;
    }

    if ($command =~ /\Aai_(?:suggest|draft|translate|rewrite|seo|seo_rewrite|kiosk)\z/) {
        my $article_id = '';
        my $error = run_admin_action(sub {
            $article_id = save_article();
            perform_ai_action($article_id, $command);
        });
        if ($error) {
            render_form(load_article($article_id || $params{id} || '') || blank_article(), $lang->t('admin.article.edit', 'Edit Article'), $error);
            exit;
        }
        my $notice_action = $command eq 'ai_suggest' ? 'done' : $command;
        Mark6::CGI::redirect('articles.cgi?command=edit&id=' . Mark6::CGI::url_encode($article_id) . '&ai=' . Mark6::CGI::url_encode($notice_action) . '#ai-assist');
        exit;
    }

    if ($command eq 'ai_apply_selected') {
        my $article_id = '';
        my $notice_action = 'applied';
        my $error = run_admin_action(sub {
            $article_id = save_article();
            my @actions = selected_ai_apply_actions();
            die "Choose an AI result to apply" unless @actions;
            $notice_action = $actions[0] eq 'tags' ? 'tags_applied'
                : $actions[0] eq 'kiosk' ? 'kiosk_applied'
                : 'applied'
                if @actions == 1;
            for my $action (@actions) {
                if ($action eq 'tags') {
                    apply_ai_tags($article_id);
                }
                elsif ($action eq 'kiosk') {
                    apply_ai_kiosk($article_id);
                }
                else {
                    apply_ai_result($article_id, $action);
                }
            }
        });
        if ($error) {
            render_form(load_article($article_id || $params{id} || '') || blank_article(), $lang->t('admin.article.edit', 'Edit Article'), $error);
            exit;
        }
        Mark6::CGI::redirect('articles.cgi?command=edit&id=' . Mark6::CGI::url_encode($article_id) . '&ai=' . Mark6::CGI::url_encode($notice_action) . '#article-editor');
        exit;
    }

    if ($command =~ /\Aai_apply_(draft|rewrite|seo_rewrite|translation)\z/) {
        my $action = $1;
        my $article_id = '';
        my $error = run_admin_action(sub {
            $article_id = save_article();
            apply_ai_result($article_id, $action);
        });
        if ($error) {
            render_form(load_article($article_id || $params{id} || '') || blank_article(), $lang->t('admin.article.edit', 'Edit Article'), $error);
            exit;
        }
        Mark6::CGI::redirect('articles.cgi?command=edit&id=' . Mark6::CGI::url_encode($article_id) . '&ai=applied#article-editor');
        exit;
    }

    if ($command eq 'ai_apply_tags') {
        my $article_id = '';
        my $error = run_admin_action(sub {
            $article_id = save_article();
            apply_ai_tags($article_id);
        });
        if ($error) {
            render_form(load_article($article_id || $params{id} || '') || blank_article(), $lang->t('admin.article.edit', 'Edit Article'), $error);
            exit;
        }
        Mark6::CGI::redirect('articles.cgi?command=edit&id=' . Mark6::CGI::url_encode($article_id) . '&ai=tags_applied#article-editor');
        exit;
    }

    if ($command eq 'ai_apply_kiosk') {
        my $article_id = '';
        my $error = run_admin_action(sub {
            $article_id = save_article();
            apply_ai_kiosk($article_id);
        });
        if ($error) {
            render_form(load_article($article_id || $params{id} || '') || blank_article(), $lang->t('admin.article.edit', 'Edit Article'), $error);
            exit;
        }
        Mark6::CGI::redirect('articles.cgi?command=edit&id=' . Mark6::CGI::url_encode($article_id) . '&ai=kiosk_applied#article-editor');
        exit;
    }

    if ($command eq 'reorder') {
        my $error = run_admin_action(sub {
            reorder_articles($params{id} || '', $params{order_action} || '', $params{order_position} || '');
        });
        if ($error) {
            render_page($lang->t('admin.article.reorder_error', 'Reorder Error'), qq|<p class="error">$error</p>|);
            exit;
        }
        Mark6::CGI::redirect('articles.cgi');
        exit;
    }

    if ($command eq 'delete') {
        my $error = run_admin_action(sub { delete_article($params{id} || '') });
        if ($error) {
            render_page($lang->t('admin.article.delete_error', 'Delete Error'), qq|<p class="error">$error</p>|);
            exit;
        }
        Mark6::CGI::redirect('articles.cgi');
        exit;
    }
}

if ($command eq 'new') {
    render_form(blank_article(), $lang->t('admin.article.new', 'New Article'));
}
elsif ($command eq 'edit') {
    my $article = load_article($params{id} || '');
    $article ? render_form($article, $lang->t('admin.article.edit', 'Edit Article')) : render_page($lang->t('admin.common.not_found', 'Not Found'), '<p class="error">' . h($lang->t('admin.article.not_found', 'Article not found.')) . '</p>');
}
else {
    render_list();
}

sub render_list {
    my @articles = grep { ($_->{status} || '') ne 'deleted' } load_articles();
    my $rows = @articles ? join("\n", map { article_row($_) } @articles) : '<p class="empty">' . h($lang->t('admin.article.empty', 'No articles yet.')) . '</p>';
    my $page_title = h($lang->t('admin.article.title', 'Articles'));
    my $new_label = h($lang->t('admin.article.new', 'New Article'));

    render_page($lang->t('admin.article.title', 'Articles'), <<"HTML");
<section class="article-detail">
  <div class="admin-toolbar"><a class="button" href="articles.cgi?command=new">$new_label</a></div>
  <h1>$page_title</h1>
  <div class="admin-list">$rows</div>
</section>
HTML
}

sub article_row {
    my ($article) = @_;
    my $id = Mark6::CGI::escape_html($article->{id} || '');
    Mark6::Article::normalize($article, $config);
    my $title = Mark6::CGI::escape_html(Mark6::Article::title_for($article, $lang->code, $config));
    my $raw_status = ($article->{status} || 'draft') eq 'published' ? 'published' : 'draft';
    my $status_key = $raw_status eq 'published' ? 'admin.article.status_published' : 'admin.article.status_draft';
    my $status = h($lang->t($status_key, ucfirst $raw_status));
    my $date = Mark6::CGI::escape_html(format_date($article->{created_at} || ''));
    my $sort_order = h(article_sort_order($article));
    my $translations = translation_status_summary($article);
    my $csrf = Mark6::CGI::escape_html($session->{csrf_token} || '');
    my $view_url = Mark6::CGI::escape_html(public_article_url($article));
    my $view_label = h($lang->t('admin.common.view', 'View'));
    my $edit_label = h($lang->t('admin.common.edit', 'Edit'));
    my $delete_label = h($lang->t('admin.common.delete', 'Delete'));
    my $order_label = h($lang->t('admin.article.order', 'Order'));
    my $top_label = h($lang->t('admin.article.order_top', 'Top'));
    my $up_label = h($lang->t('admin.article.order_up', 'Up'));
    my $down_label = h($lang->t('admin.article.order_down', 'Down'));
    my $bottom_label = h($lang->t('admin.article.order_bottom', 'Bottom'));
    my $set_label = h($lang->t('admin.article.order_set', 'Set'));
    my $confirm_delete = js_string($lang->t('admin.article.confirm_delete', 'Delete this article?'));

    return <<"HTML";
<article class="admin-row">
  <div>
    <strong>$title</strong>
    <div class="meta">$status / $date / ID $id / $order_label $sort_order</div>
    <div class="meta translation-state">$translations</div>
  </div>
  <div class="admin-actions">
    <form class="order-actions" method="post" action="articles.cgi">
      <input type="hidden" name="command" value="reorder">
      <input type="hidden" name="id" value="$id">
      <input type="hidden" name="csrf_token" value="$csrf">
      <button class="button secondary compact" type="submit" name="order_action" value="top">$top_label</button>
      <button class="button secondary compact" type="submit" name="order_action" value="up">$up_label</button>
      <button class="button secondary compact" type="submit" name="order_action" value="down">$down_label</button>
      <button class="button secondary compact" type="submit" name="order_action" value="bottom">$bottom_label</button>
      <input class="order-position" name="order_position" type="number" min="1" value="$sort_order">
      <button class="button secondary compact" type="submit" name="order_action" value="set">$set_label</button>
    </form>
    <div class="row-actions">
      <a class="button secondary compact" href="$view_url" target="_blank" rel="noopener">$view_label</a>
      <a class="button secondary compact" href="articles.cgi?command=edit&amp;id=$id">$edit_label</a>
      <form method="post" action="articles.cgi" onsubmit="return confirm('$confirm_delete');">
        <input type="hidden" name="command" value="delete">
        <input type="hidden" name="id" value="$id">
        <input type="hidden" name="csrf_token" value="$csrf">
        <button class="button secondary compact" type="submit">$delete_label</button>
      </form>
    </div>
  </div>
</article>
HTML
}

sub render_form {
    my ($article, $heading, $error) = @_;
    Mark6::Article::normalize($article, $config);
    my $id = Mark6::CGI::escape_html($article->{id} || '');
    my $node = Mark6::CGI::escape_html($article->{node} || $config->{site}{node} || 'oita360');
    my $slug = Mark6::CGI::escape_html($article->{slug} || '');
    my $image = Mark6::CGI::escape_html($article->{image} || '');
    my $default_lang = Mark6::CGI::escape_html(Mark6::Article::default_lang($article, $config));
    my $language_fields = language_fields($article);
    my $kiosk_fields = kiosk_fields($article);
    my $media_options = media_options($article->{image} || '');
    my $ai_panel = ai_panel($article);
    my $csrf = Mark6::CGI::escape_html($session->{csrf_token} || '');
    my $status = $article->{status} || 'draft';
    my $draft_selected = $status eq 'draft' ? 'selected' : '';
    my $published_selected = $status eq 'published' ? 'selected' : '';
    my $safe_heading = h($heading);
    my $articles_label = h($lang->t('admin.article.title', 'Articles'));
    my $node_label = h($lang->t('admin.article.node', 'Section'));
    my $slug_label = h($lang->t('admin.article.slug', 'URL slug'));
    my $status_label = h($lang->t('admin.article.status', 'Status'));
    my $draft_label = h($lang->t('admin.article.status_draft', 'Draft'));
    my $published_label = h($lang->t('admin.article.status_published', 'Published'));
    my $main_image_label = h($lang->t('admin.article.main_image', 'Main image'));
    my $no_image_label = h($lang->t('admin.article.no_image', 'No image'));
    my $image_path_label = h($lang->t('admin.article.image_path', 'Image path'));
    my $save_label = h($lang->t('admin.common.save', 'Save'));
    my $notice = ai_notice($params{ai} || '');
    my $error_html = $error ? qq|<p class="error">$error</p>| : '';

    render_page($heading, <<"HTML");
<section class="article-detail">
  <a class="back-link" href="articles.cgi">$articles_label</a>
  <h1>$safe_heading</h1>
  $notice
  $error_html
  <form id="article-editor" class="admin-form" method="post" action="articles.cgi">
    <input type="hidden" name="command" value="save">
    <input type="hidden" name="id" value="$id">
    <input type="hidden" name="csrf_token" value="$csrf">
    <input type="hidden" name="default_lang" value="$default_lang">
    <label>$node_label<br><input name="node" type="text" value="$node" required></label>
    <label>$slug_label<br><input name="slug" type="text" value="$slug" placeholder="beppu-station"></label>
    <label>$status_label<br>
      <select name="status">
        <option value="draft" $draft_selected>$draft_label</option>
        <option value="published" $published_selected>$published_label</option>
      </select>
    </label>
    <label>$main_image_label<br>
      <select name="image">
        <option value="">$no_image_label</option>
        $media_options
      </select>
    </label>
    <label>$image_path_label<br><input name="image_manual" type="text" value="$image"></label>
    $language_fields
    $kiosk_fields
    $ai_panel
    <button type="submit">$save_label</button>
  </form>
  <script>
  (() => {
    for (const group of document.querySelectorAll('.language-editor, .tabbed-panel')) {
      const tabs = Array.from(group.querySelectorAll('[data-lang-tab]'));
      const panels = Array.from(group.querySelectorAll('.lang-panel'));
      for (const tab of tabs) {
        tab.addEventListener('click', () => {
          for (const item of tabs) item.classList.toggle('active', item === tab);
          for (const panel of panels) {
            const active = panel.id === tab.dataset.langTab;
            panel.hidden = !active;
            panel.classList.toggle('active', active);
          }
        });
      }
    }
  })();
  </script>
</section>
HTML
}

sub save_article {
    my $id = $params{id} || time;
    die "Invalid article id" unless $id =~ /\A[0-9A-Za-z_-]+\z/;

    my $existing = load_article($id) || {};
    Mark6::Article::normalize($existing, $config);
    my $now = iso_now();
    my $default_lang = normalize_lang($params{default_lang} || $existing->{default_lang} || $config->{site}{language} || 'ja');
    my $langs = collect_langs();
    $langs->{$default_lang}{title} ||= $params{title} || '';
    $langs->{$default_lang}{description} ||= $params{intro} || '';
    $langs->{$default_lang}{body} ||= $params{body} || '';
    my $default_title = $langs->{$default_lang}{title} || $existing->{title} || 'Untitled';
    my $default_description = $langs->{$default_lang}{description} || $existing->{intro} || '';
    my $default_body = $langs->{$default_lang}{body} || $existing->{body} || '';
    my $translation_status = translation_status_after_save($existing, $langs, $default_lang);
    my $node = safe_segment($params{node} || $existing->{node} || $config->{site}{node} || 'oita360');
    save_node_labels($node);

    my $article = {
        %{$existing},
        id         => "$id",
        type       => 'article',
        status     => normalize_status($params{status}),
        default_lang => $default_lang,
        langs      => $langs,
        translation_status => $translation_status,
        title      => $default_title,
        slug       => safe_segment($params{slug} || $existing->{slug} || $id),
        node       => $node,
        tags       => common_tags($existing, $default_lang),
        tag_langs  => collect_tag_langs($existing, $default_lang),
        image      => safe_image_path($params{image} || $params{image_manual} || ''),
        intro      => $default_description,
        body       => $default_body,
        writer_id  => $existing->{writer_id} || $user->{id},
        created_at => $existing->{created_at} || $now,
        updated_at => $now,
        sort_order => article_initial_sort_order($existing),
        ai         => $existing->{ai} || {
            summary           => '',
            suggested_tags    => [],
            seo_description   => '',
            last_processed_at => '',
        },
        kiosk      => collect_kiosk($existing),
    };

    my $path = $store->write_json($article, 'dat', 'articles', "$id.json");
    die "Article JSON was not created at $path" unless -e $path;
    return "$id";
}

sub perform_ai_action {
    my ($id, $command) = @_;
    die $lang->t('admin.ai.disabled_error', 'AI assist is disabled.') unless $config->{features}{ai};

    my $article = load_article($id) or die "Article not found";
    Mark6::Article::normalize($article, $config);
    my $assistant = Mark6::AI->new(config => $config);
    $article->{ai} ||= {};
    my $default_lang = Mark6::Article::default_lang($article, $config);

    if ($command eq 'ai_suggest') {
        $article->{ai} = { %{$article->{ai}}, %{$assistant->suggest_article(article => $article)} };
    }
    elsif ($command eq 'ai_draft') {
        $article->{ai}{draft} = $assistant->draft_body(article => $article, lang => $default_lang);
    }
    elsif ($command eq 'ai_translate') {
        my $target_lang = normalize_lang($params{ai_target_lang} || '');
        die "Choose a translation language different from the default language" if $target_lang eq $default_lang;
        $article->{ai}{translations} ||= {};
        $article->{ai}{translations}{$target_lang} = $assistant->translate_article(
            article     => $article,
            source_lang => $default_lang,
            target_lang => $target_lang,
        );
    }
    elsif ($command eq 'ai_rewrite') {
        $article->{ai}{rewrite} = $assistant->rewrite_body(article => $article, lang => $default_lang);
    }
    elsif ($command eq 'ai_seo_rewrite') {
        $article->{ai}{seo_rewrite} = $assistant->seo_rewrite_body(
            article => $article,
            lang    => $default_lang,
            seo     => $article->{ai}{seo} || {},
        );
    }
    elsif ($command eq 'ai_seo') {
        my $seo = $assistant->diagnose_seo(article => $article, lang => $default_lang);
        $seo->{lang} = $default_lang;
        $article->{ai}{seo} = $seo;
    }
    elsif ($command eq 'ai_kiosk') {
        my $kiosk = $assistant->suggest_kiosk(article => $article, lang => $default_lang);
        $kiosk->{lang} = $default_lang;
        $article->{ai}{kiosk} = $kiosk;
    }
    else {
        die "Unknown AI action";
    }

    my $path = $store->write_json($article, 'dat', 'articles', "$id.json");
    die "Article JSON was not updated at $path" unless -e $path;
}

sub perform_ai_batch {
    my ($id) = @_;
    my @commands = selected_ai_commands();
    die "Choose at least one AI action" unless @commands;

    for my $command (@commands) {
        perform_ai_action($id, $command);
    }
}

sub selected_ai_commands {
    my @commands;
    push @commands, 'ai_draft' if ($params{ai_run_draft} || '') eq '1';
    push @commands, 'ai_translate' if ($params{ai_run_translate} || '') eq '1';
    push @commands, 'ai_rewrite' if ($params{ai_run_rewrite} || '') eq '1';
    push @commands, 'ai_seo' if ($params{ai_run_seo} || '') eq '1';
    push @commands, 'ai_seo_rewrite' if ($params{ai_run_seo_rewrite} || '') eq '1';
    push @commands, 'ai_kiosk' if ($params{ai_run_kiosk} || '') eq '1';
    return @commands;
}

sub apply_ai_result {
    my ($id, $action) = @_;
    my $article = load_article($id) or die "Article not found";
    Mark6::Article::normalize($article, $config);
    my $ai = $article->{ai} || {};
    my $default_lang = Mark6::Article::default_lang($article, $config);

    if ($action eq 'draft' || $action eq 'rewrite' || $action eq 'seo_rewrite') {
        my $result = $ai->{$action} || {};
        die "No AI $action result is available" unless ($result->{body} || '') ne '';
        my $changed = ($article->{langs}{$default_lang}{body} || '') ne ($result->{body} || '');
        $article->{langs}{$default_lang}{body} = $result->{body};
        mark_translations_outdated($article, $default_lang) if $changed;
    }
    elsif ($action eq 'translation') {
        my $target_lang = normalize_lang($params{ai_target_lang} || '');
        my $result = ($ai->{translations} || {})->{$target_lang} || {};
        die "No AI translation result is available" unless ($result->{body} || '') ne '' || ($result->{title} || '') ne '';
        $article->{langs}{$target_lang} = {
            title       => $result->{title} || '',
            description => $result->{description} || '',
            body        => $result->{body} || '',
        };
        $article->{translation_status} ||= {};
        $article->{translation_status}{$target_lang} = { state => 'translated' };
    }
    else {
        die "Unknown AI result";
    }

    my $default = $article->{langs}{$default_lang} || {};
    $article->{title} = $default->{title} || 'Untitled';
    $article->{intro} = $default->{description} || '';
    $article->{body} = $default->{body} || '';
    $article->{updated_at} = iso_now();
    my $path = $store->write_json($article, 'dat', 'articles', "$id.json");
    die "Article JSON was not updated at $path" unless -e $path;
}

sub apply_ai_tags {
    my ($id) = @_;
    my $article = load_article($id) or die "Article not found";
    Mark6::Article::normalize($article, $config);
    my $suggested = (($article->{ai} || {})->{seo} || {})->{suggested_tags};
    die "No AI tag suggestions are available" unless ref($suggested) eq 'ARRAY' && @{$suggested};

    my $default_lang = Mark6::Article::default_lang($article, $config);
    my $current_lang_tags = Mark6::Article::tags_for_lang($article, $default_lang, $config);
    my @merged = merge_unique_tags($current_lang_tags, $suggested);

    $article->{tags} = \@merged;
    $article->{tag_langs} ||= {};
    $article->{tag_langs}{$default_lang} = \@merged;
    $article->{updated_at} = iso_now();
    my $path = $store->write_json($article, 'dat', 'articles', "$id.json");
    die "Article JSON was not updated at $path" unless -e $path;
}

sub merge_unique_tags {
    my (@groups) = @_;
    my %seen;
    my @merged;
    for my $group (@groups) {
        next unless ref($group) eq 'ARRAY';
        for my $tag (@{$group}) {
            next unless defined $tag;
            $tag =~ s/^\s+|\s+$//g;
            next if $tag eq '';
            my $key = lc $tag;
            next if $seen{$key}++;
            push @merged, $tag;
        }
    }
    return @merged;
}

sub apply_ai_kiosk {
    my ($id) = @_;
    my $article = load_article($id) or die "Article not found";
    my $suggested = (($article->{ai} || {})->{kiosk} || {})->{kiosk_items};
    die "No AI Kiosk suggestions are available" unless ref($suggested) eq 'ARRAY' && @{$suggested};

    my $kiosk = ref($article->{kiosk}) eq 'HASH' ? $article->{kiosk} : {};
    my @existing = ref($kiosk->{items}) eq 'ARRAY' ? @{$kiosk->{items}} : ();
    my %seen;
    my @items;

    for my $item (@existing, @{$suggested}) {
        next unless ref($item) eq 'HASH';
        my $label = clean_text($item->{label} || '');
        my $keyword = clean_text($item->{keyword} || '');
        next if $label eq '' && $keyword eq '';
        $label = $keyword if $label eq '';
        $keyword = $label if $keyword eq '';
        my $key = lc "$label\0$keyword";
        next if $seen{$key}++;
        push @items, {
            label   => $label,
            keyword => $keyword,
        };
        last if @items >= 5;
    }

    $article->{kiosk} = {
        enabled => @items ? JSON::PP::true : JSON::PP::false,
        items   => \@items,
    };
    $article->{updated_at} = iso_now();
    my $path = $store->write_json($article, 'dat', 'articles', "$id.json");
    die "Article JSON was not updated at $path" unless -e $path;
}

sub delete_article {
    my ($id) = @_;
    return unless $id =~ /\A[0-9A-Za-z_-]+\z/;
    my $path = $store->path('dat', 'articles', "$id.json");
    unlink $path or die "Cannot delete article JSON $path: $!" if -e $path;
}

sub reorder_articles {
    my ($id, $action, $position) = @_;
    die "Invalid article id" unless $id =~ /\A[0-9A-Za-z_-]+\z/;
    die "Invalid order action" unless $action =~ /\A(?:top|up|down|bottom|set)\z/;

    my @articles = grep { ($_->{status} || '') ne 'deleted' } load_articles();
    return unless @articles > 1;

    my ($index) = grep { ($articles[$_]{id} || '') eq $id } 0 .. $#articles;
    die "Article not found" unless defined $index;

    my $article = splice @articles, $index, 1;
    my $target = $index;
    if ($action eq 'top') {
        $target = 0;
    }
    elsif ($action eq 'up') {
        $target = $index > 0 ? $index - 1 : 0;
    }
    elsif ($action eq 'down') {
        $target = $index < @articles ? $index + 1 : scalar @articles;
    }
    elsif ($action eq 'bottom') {
        $target = scalar @articles;
    }
    elsif ($action eq 'set') {
        die "Invalid order position" unless defined $position && $position =~ /\A[0-9]+\z/;
        $target = int($position) - 1;
        $target = 0 if $target < 0;
        $target = scalar @articles if $target > @articles;
    }

    splice @articles, $target, 0, $article;
    for my $i (0 .. $#articles) {
        my $item = $articles[$i];
        $item->{sort_order} = ($i + 1) * 10;
        $item->{updated_at} = iso_now();
        my $item_id = $item->{id} || '';
        die "Invalid article id" unless $item_id =~ /\A[0-9A-Za-z_-]+\z/;
        my $path = $store->write_json($item, 'dat', 'articles', "$item_id.json");
        die "Article JSON was not updated at $path" unless -e $path;
    }
}

sub load_articles {
    my $dir = "$ROOT/dat/articles";
    return () unless -d $dir;

    opendir my $dh, $dir or die "Cannot open $dir: $!";
    my @files = grep { /\.json\z/ } readdir $dh;
    closedir $dh;

    my @articles;
    for my $file (@files) {
        my $article = $store->read_json('dat', 'articles', $file);
        push @articles, $article if $article;
    }

    return sort article_sort @articles;
}

sub load_article {
    my ($id) = @_;
    return undef unless $id =~ /\A[0-9A-Za-z_-]+\z/;
    return $store->read_json('dat', 'articles', "$id.json");
}

sub blank_article {
    return {
        id => '',
        status => 'draft',
        default_lang => 'ja',
        langs => {
            ja => { title => '', description => '', body => '' },
            en => { title => '', description => '', body => '' },
        },
        title => '',
        node => $config->{site}{node} || 'oita360',
        slug => '',
        tags => [],
        image => '',
        intro => '',
        body => '',
    };
}

sub language_fields {
    my ($article) = @_;
    my $legend = h($lang->t('admin.article.content', 'Content'));
    my $default_lang = Mark6::Article::default_lang($article, $config);
    my $node = $article->{node} || $config->{site}{node} || 'oita360';
    my $node_labels = node_labels($node);
    my @tab_controls;
    my @panels;

    for my $lang_code (@article_langs) {
        my $entry = $article->{langs}{$lang_code} || {};
        my $label = uc($lang_code) . ' - ' . translation_state_label($article, $lang_code);
        my $title = Mark6::CGI::escape_html($entry->{title} || '');
        my $description = Mark6::CGI::escape_html($entry->{description} || '');
        my $body = Mark6::CGI::escape_html($entry->{body} || '');
        my $title_label = h($lang->t('admin.article.field_title', 'Title'));
        my $section_label = h($lang->t('admin.article.node_label', 'Section label'));
        my $tags_label = h($lang->t('admin.article.tags', 'Tags'));
        my $description_label = h($lang->t('admin.article.field_description_html', 'Description HTML'));
        my $body_label = h($lang->t('admin.article.field_body_html', 'Body HTML'));
        my $section_value = h($node_labels->{$lang_code} || $node);
        my $tags = Mark6::Article::tags_for_lang($article, $lang_code, $config);
        my $tag_value = h(join(', ', @{$tags}));
        my $active = $lang_code eq $default_lang ? ' active' : '';
        my $hidden = $lang_code eq $default_lang ? '' : ' hidden';
        my $tab_id = Mark6::CGI::escape_html("lang-panel-$lang_code");

        push @tab_controls, qq|      <button class="lang-tab$active" type="button" data-lang-tab="$tab_id">$label</button>|;
        push @panels, <<"HTML";
      <section id="$tab_id" class="lang-panel$active"$hidden>
        <label>$title_label<br><input name="title_$lang_code" type="text" value="$title"></label>
        <label>$section_label<br><input name="node_label_$lang_code" type="text" value="$section_value"></label>
        <label>$tags_label<br><input name="tags_$lang_code" type="text" value="$tag_value"></label>
        <label>$description_label<br><textarea name="description_$lang_code" rows="5">$description</textarea></label>
        <label>$body_label<br><textarea name="body_$lang_code" rows="12">$body</textarea></label>
      </section>
HTML
    }

    return <<"HTML";
    <fieldset class="language-editor">
      <legend>$legend</legend>
      <div class="lang-tabs" role="tablist">
@{[join "\n", @tab_controls]}
      </div>
      <div class="lang-panels">
@{[join "\n", @panels]}
      </div>
    </fieldset>
HTML
}

sub kiosk_fields {
    my ($article) = @_;
    my $kiosk = ref($article->{kiosk}) eq 'HASH' ? $article->{kiosk} : {};
    my @items = ref($kiosk->{items}) eq 'ARRAY' ? @{$kiosk->{items}} : ();
    my $checked = $kiosk->{enabled} ? 'checked' : '';
    my $legend = h($lang->t('admin.article.kiosk', 'Kiosk'));
    my $enabled_label = h($lang->t('admin.article.kiosk_enabled', 'Show Kiosk links after this article'));
    my $label_text = h($lang->t('admin.article.kiosk_label', 'Label'));
    my $keyword_text = h($lang->t('admin.article.kiosk_keyword', 'Keyword'));
    my $help = h($lang->t('admin.article.kiosk_help', 'Creates search links only. Prices, stock, reviews, and product images are not stored.'));
    my @rows;

    for my $index (0 .. 4) {
        my $item = ref($items[$index]) eq 'HASH' ? $items[$index] : {};
        my $number = $index + 1;
        my $label = h($item->{label} || '');
        my $keyword = h($item->{keyword} || '');
        push @rows, <<"HTML";
      <div class="kiosk-admin-row">
        <label>$label_text $number<br><input name="kiosk_label_$number" type="text" value="$label"></label>
        <label>$keyword_text $number<br><input name="kiosk_keyword_$number" type="text" value="$keyword"></label>
      </div>
HTML
    }

    return <<"HTML";
    <fieldset>
      <legend>$legend</legend>
      <label><input name="kiosk_enabled" type="checkbox" value="1" $checked> $enabled_label</label>
      <p class="meta">$help</p>
      <div class="kiosk-admin-grid">
@{[join '', @rows]}      </div>
    </fieldset>
HTML
}

sub translation_status_summary {
    my ($article) = @_;
    return join ' / ', map {
        uc($_) . ': ' . translation_state_label($article, $_)
    } @article_langs;
}

sub translation_state_label {
    my ($article, $lang_code) = @_;
    my $state = Mark6::Article::translation_state($article, $lang_code, $config);
    my %keys = (
        source       => 'admin.article.translation_source',
        translated   => 'admin.article.translation_translated',
        untranslated => 'admin.article.translation_untranslated',
        outdated     => 'admin.article.translation_outdated',
    );
    my %fallbacks = (
        source       => 'Source',
        translated   => 'Translated',
        untranslated => 'Untranslated',
        outdated     => 'Needs update',
    );
    return h($lang->t($keys{$state} || $keys{untranslated}, $fallbacks{$state} || $fallbacks{untranslated}));
}

sub translation_status_after_save {
    my ($existing, $langs, $default_lang) = @_;
    my %status = ref($existing->{translation_status}) eq 'HASH' ? %{$existing->{translation_status}} : ();
    my $previous_default = Mark6::Article::default_lang($existing, $config);
    my $has_existing = ($existing->{id} || '') ne '';
    my $source_changed = $has_existing && (
        $previous_default ne $default_lang ||
        language_entry_changed($existing->{langs}{$default_lang}, $langs->{$default_lang})
    );

    for my $lang_code (@article_langs) {
        next if $lang_code eq $default_lang;
        if (!language_entry_has_content($langs->{$lang_code})) {
            $status{$lang_code} = { state => 'untranslated' };
        }
        elsif ($source_changed) {
            $status{$lang_code} = { state => 'outdated' };
        }
        elsif (language_entry_changed($existing->{langs}{$lang_code}, $langs->{$lang_code})) {
            $status{$lang_code} = { state => 'translated' };
        }
        elsif ((($status{$lang_code} || {})->{state} || '') ne 'outdated') {
            $status{$lang_code} = { state => 'translated' };
        }
    }

    return \%status;
}

sub mark_translations_outdated {
    my ($article, $default_lang) = @_;
    $article->{translation_status} ||= {};
    for my $lang_code (@article_langs) {
        next if $lang_code eq $default_lang;
        $article->{translation_status}{$lang_code} = {
            state => language_entry_has_content($article->{langs}{$lang_code}) ? 'outdated' : 'untranslated',
        };
    }
}

sub language_entry_changed {
    my ($before, $after) = @_;
    $before ||= {};
    $after ||= {};
    for my $field (qw(title description body)) {
        return 1 if ($before->{$field} || '') ne ($after->{$field} || '');
    }
    return 0;
}

sub language_entry_has_content {
    my ($entry) = @_;
    return 0 unless ref($entry) eq 'HASH';
    return scalar grep { defined($entry->{$_}) && $entry->{$_} =~ /\S/ } qw(title description body);
}

sub ai_panel {
    my ($article) = @_;
    return '' unless $config->{features}{ai};

    my $ai = $article->{ai} || {};
    my $legend = h($lang->t('admin.ai.legend', 'AI assist'));
    my $help = h($lang->t('admin.ai.help', 'The article is saved before each AI action. Review a generated result before applying it.'));
    my $draft_label = h($lang->t('admin.ai.draft', 'Body draft'));
    my $translate_label = h($lang->t('admin.ai.translate', 'Translate'));
    my $rewrite_label = h($lang->t('admin.ai.rewrite', 'Rewrite'));
    my $seo_label = h($lang->t('admin.ai.seo', 'SEO diagnosis'));
    my $seo_rewrite_label = h($lang->t('admin.ai.seo_rewrite', 'SEO rewrite'));
    my $kiosk_label = h($lang->t('admin.ai.kiosk', 'Kiosk suggestions'));
    my $tag_add_label = h($lang->t('admin.ai.add_tags', 'Add suggested tags'));
    my $kiosk_add_label = h($lang->t('admin.ai.add_kiosk', 'Add Kiosk suggestions'));
    my $apply_label = h($lang->t('admin.ai.apply', 'Apply to article'));
    my $run_selected_label = h($lang->t('admin.ai.run_selected', 'Run selected AI actions'));
    my $apply_selected_label = h($lang->t('admin.ai.apply_selected', 'Apply selected AI results'));
    my $apply_target_label = h($lang->t('admin.ai.apply_target', 'Results to apply'));
    my $target_label = h($lang->t('admin.ai.target_lang', 'Translation language'));
    my $draft = $ai->{draft} || {};
    my $rewrite = $ai->{rewrite} || {};
    my $seo_rewrite = $ai->{seo_rewrite} || {};
    my $target_lang = ai_target_lang($article);
    my $translation = ($ai->{translations} || {})->{$target_lang} || {};
    my $seo = $ai->{seo} || {};
    my $kiosk = $ai->{kiosk} || {};
    my $draft_body = h($draft->{body} || '');
    my $rewrite_body = h($rewrite->{body} || '');
    my $seo_rewrite_body = h($seo_rewrite->{body} || '');
    my $translation_title = h($translation->{title} || '');
    my $translation_description = h($translation->{description} || '');
    my $translation_body = h($translation->{body} || '');
    my $seo_description = h($seo->{seo_description} || '');
    my $seo_tags = h(join(', ', @{$seo->{suggested_tags} || []}));
    my $seo_diagnosis = h($seo->{diagnosis} || '');
    my $kiosk_items = ai_kiosk_items($kiosk);
    my $target_options = ai_target_options($article, $target_lang);
    my $draft_meta = ai_result_meta($draft);
    my $rewrite_meta = ai_result_meta($rewrite);
    my $seo_rewrite_meta = ai_result_meta($seo_rewrite);
    my $translation_meta = ai_result_meta($translation);
    my $seo_meta = ai_result_meta($seo);
    my $kiosk_meta = ai_result_meta($kiosk);
    my $has_seo = ($seo->{last_processed_at} || '') ne '' || ($seo->{diagnosis} || '') ne '' || ($seo->{seo_description} || '') ne '' || @{$seo->{suggested_tags} || []};
    my $apply_controls = ai_apply_controls(
        draft       => $draft,
        rewrite     => $rewrite,
        seo_rewrite => $seo_rewrite,
        translation => $translation,
        seo         => $seo,
        kiosk       => $kiosk,
        labels      => {
            draft       => $draft_label,
            rewrite     => $rewrite_label,
            seo_rewrite => $seo_rewrite_label,
            translation => $translate_label,
            tags        => $tag_add_label,
            kiosk       => $kiosk_add_label,
        },
    );
    my $apply_panel = $apply_controls ne '' ? <<"HTML" : '';
      <div class="ai-apply-bar">
        <div>
          <strong>$apply_target_label</strong>
          <div class="ai-apply-options">$apply_controls</div>
        </div>
        <button type="submit" name="command" value="ai_apply_selected">$apply_selected_label</button>
      </div>
HTML

    return <<"HTML";
    <fieldset id="ai-assist">
      <legend>$legend</legend>
      <p class="meta">$help</p>
      <div class="tabbed-panel ai-tabbed">
        <div class="lang-tabs ai-tabs" role="tablist">
          <button class="lang-tab active" type="button" data-lang-tab="ai-panel-writing">$draft_label / $rewrite_label</button>
          <button class="lang-tab" type="button" data-lang-tab="ai-panel-translate">$translate_label</button>
          <button class="lang-tab" type="button" data-lang-tab="ai-panel-seo">$seo_label</button>
          <button class="lang-tab" type="button" data-lang-tab="ai-panel-seo-rewrite">$seo_rewrite_label</button>
        </div>
        <div class="lang-panels">
          <section id="ai-panel-writing" class="lang-panel active">
            <div class="ai-action-grid">
              <label class="ai-toggle"><input name="ai_run_draft" type="checkbox" value="1"> $draft_label</label>
              <label class="ai-toggle"><input name="ai_run_rewrite" type="checkbox" value="1"> $rewrite_label</label>
            </div>
            <div class="ai-result-grid">
              <section class="ai-result-box">
                <h3>$draft_label</h3>
                <textarea rows="8" readonly>$draft_body</textarea>
                $draft_meta
              </section>
              <section class="ai-result-box">
                <h3>$rewrite_label</h3>
                <textarea rows="8" readonly>$rewrite_body</textarea>
                $rewrite_meta
              </section>
            </div>
          </section>
          <section id="ai-panel-translate" class="lang-panel" hidden>
            <label class="ai-toggle"><input name="ai_run_translate" type="checkbox" value="1"> $translate_label</label>
            <label>$target_label<br>
              <select name="ai_target_lang">$target_options</select>
            </label>
            <section class="ai-result-box">
              <h3>$translate_label</h3>
              <label>Title<br><input type="text" value="$translation_title" readonly></label>
              <label>Description HTML<br><textarea rows="4" readonly>$translation_description</textarea></label>
              <label>Body HTML<br><textarea rows="8" readonly>$translation_body</textarea></label>
              $translation_meta
            </section>
          </section>
          <section id="ai-panel-seo" class="lang-panel" hidden>
            <div class="ai-action-grid">
              <label class="ai-toggle"><input name="ai_run_seo" type="checkbox" value="1"> $seo_label</label>
              <label class="ai-toggle"><input name="ai_run_kiosk" type="checkbox" value="1"> $kiosk_label</label>
            </div>
            <div class="ai-result-grid">
              <section class="ai-result-box">
                <h3>$seo_label</h3>
                <label>SEO description<br><textarea rows="3" readonly>$seo_description</textarea></label>
                <label>Suggested tags<br><input type="text" value="$seo_tags" readonly onclick="this.select()"></label>
                <label>Diagnosis<br><textarea rows="4" readonly>$seo_diagnosis</textarea></label>
                $seo_meta
              </section>
              <section class="ai-result-box">
                <h3>$kiosk_label</h3>
                $kiosk_items
                $kiosk_meta
              </section>
            </div>
          </section>
          <section id="ai-panel-seo-rewrite" class="lang-panel" hidden>
            <label class="ai-toggle"><input name="ai_run_seo_rewrite" type="checkbox" value="1"> $seo_rewrite_label</label>
            <section class="ai-result-box">
              <h3>$seo_rewrite_label</h3>
              <textarea rows="8" readonly>$seo_rewrite_body</textarea>
              $seo_rewrite_meta
            </section>
          </section>
        </div>
      </div>
      <div class="admin-toolbar">
        <button type="submit" name="command" value="ai_run_selected">$run_selected_label</button>
      </div>
      $apply_panel
    </fieldset>
HTML
}

sub ai_kiosk_items {
    my ($kiosk) = @_;
    my @items = ref($kiosk->{kiosk_items}) eq 'ARRAY' ? @{$kiosk->{kiosk_items}} : ();
    return '<p class="empty">' . h($lang->t('admin.ai.kiosk_empty', 'No Kiosk suggestions yet.')) . '</p>' unless @items;

    my @rows;
    for my $item (@items) {
        next unless ref($item) eq 'HASH';
        my $label = h($item->{label} || '');
        my $keyword = h($item->{keyword} || '');
        my $reason = h($item->{reason} || '');
        push @rows, <<"HTML";
          <li>
            <strong>$label</strong>
            <span class="meta">$keyword</span>
            <span class="meta">$reason</span>
          </li>
HTML
    }
    return '<ul class="ai-kiosk-list">' . join('', @rows) . '</ul>';
}

sub ai_apply_controls {
    my (%args) = @_;
    my $labels = $args{labels} || {};
    my @options;

    push @options, [draft => $labels->{draft}] if (($args{draft} || {})->{body} || '') ne '';
    push @options, [rewrite => $labels->{rewrite}] if (($args{rewrite} || {})->{body} || '') ne '';
    push @options, [seo_rewrite => $labels->{seo_rewrite}] if (($args{seo_rewrite} || {})->{body} || '') ne '';
    my $translation = $args{translation} || {};
    push @options, [translation => $labels->{translation}] if ($translation->{body} || $translation->{title} || '') ne '';
    my $suggested = (($args{seo} || {})->{suggested_tags}) || [];
    push @options, [tags => $labels->{tags}] if ref($suggested) eq 'ARRAY' && @{$suggested};
    my $kiosk_items = (($args{kiosk} || {})->{kiosk_items}) || [];
    push @options, [kiosk => $labels->{kiosk}] if ref($kiosk_items) eq 'ARRAY' && @{$kiosk_items};

    return join "\n", map {
        my ($value, $label) = @{$_};
        qq|<label class="ai-toggle"><input name="ai_apply_$value" type="checkbox" value="1"> $label</label>|;
    } @options;
}

sub selected_ai_apply_actions {
    return grep { ($params{"ai_apply_$_"} || '') eq '1' } qw(draft rewrite seo_rewrite translation tags kiosk);
}

sub ai_result_meta {
    my ($result) = @_;
    return '' unless ($result->{last_processed_at} || '') ne '';
    my $processed_label = h($lang->t('admin.ai.last_processed_at', 'Last processed'));
    return qq|<div class="meta">$processed_label: | . h($result->{last_processed_at}) . q|</div>|;
}

sub ai_target_lang {
    my ($article) = @_;
    my $default = Mark6::Article::default_lang($article, $config);
    my $requested = normalize_lang($params{ai_target_lang} || '');
    return $requested if $requested ne $default;
    for my $candidate (@article_langs) {
        return $candidate if $candidate ne $default;
    }
    return $default;
}

sub ai_target_options {
    my ($article, $selected) = @_;
    my $default = Mark6::Article::default_lang($article, $config);
    my @options;
    for my $code (@article_langs) {
        next if $code eq $default;
        my $is_selected = $code eq $selected ? 'selected' : '';
        push @options, qq|<option value="$code" $is_selected>| . uc($code) . q|</option>|;
    }
    return join "\n", @options;
}

sub ai_notice {
    my ($action) = @_;
    return '' if $action eq '';
    my %keys = (
        ai_draft     => 'admin.ai.draft_done',
        ai_translate => 'admin.ai.translate_done',
        ai_rewrite   => 'admin.ai.rewrite_done',
        ai_seo       => 'admin.ai.seo_done',
        ai_seo_rewrite => 'admin.ai.seo_rewrite_done',
        ai_kiosk     => 'admin.ai.kiosk_done',
        selected_done => 'admin.ai.selected_done',
        tags_applied => 'admin.ai.tags_applied',
        kiosk_applied => 'admin.ai.kiosk_applied',
        ai_suggest   => 'admin.ai.done',
        applied      => 'admin.ai.applied',
    );
    my $fallback = $action eq 'applied' ? 'AI result was applied to the article.' : 'AI result was generated.';
    return '<p class="notice">' . h($lang->t($keys{$action} || 'admin.ai.done', $fallback)) . '</p>';
}

sub default_lang_options {
    my ($article) = @_;
    my $default = Mark6::Article::default_lang($article, $config);
    return join "\n", map {
        my $lang = $_;
        my $selected = $lang eq $default ? 'selected' : '';
        qq|<option value="$lang" $selected>| . uc($lang) . q|</option>|;
    } @article_langs;
}

sub collect_langs {
    my %langs;
    for my $lang (@article_langs) {
        $langs{$lang} = {
            title       => $params{"title_$lang"} || '',
            description => $params{"description_$lang"} || '',
            body        => $params{"body_$lang"} || '',
        };
    }
    return \%langs;
}

sub collect_tag_langs {
    my ($existing, $default_lang) = @_;
    my %tag_langs = ref($existing->{tag_langs}) eq 'HASH' ? %{$existing->{tag_langs}} : ();

    for my $lang_code (@article_langs) {
        if (exists $params{"tags_$lang_code"}) {
            $tag_langs{$lang_code} = parse_tags($params{"tags_$lang_code"} || '');
        }
        elsif ($lang_code eq $default_lang && exists $params{tags}) {
            $tag_langs{$lang_code} = parse_tags($params{tags} || '');
        }
        elsif (!exists $tag_langs{$lang_code}) {
            my $existing_tags = Mark6::Article::tags_for_lang($existing, $lang_code, $config);
            $tag_langs{$lang_code} = $existing_tags if @{$existing_tags};
        }
    }

    return \%tag_langs;
}

sub common_tags {
    my ($existing, $default_lang) = @_;
    return parse_tags($params{tags}) if exists $params{tags};
    return parse_tags($params{"tags_$default_lang"} || '') if exists $params{"tags_$default_lang"};
    return Mark6::Article::tags_for_lang($existing, $default_lang, $config);
    return [];
}

sub node_labels {
    my ($node) = @_;
    my $nodes = ref($config->{nodes}) eq 'HASH' ? $config->{nodes} : {};
    my $entry = ref($nodes->{$node}) eq 'HASH' ? $nodes->{$node} : {};
    my $labels = ref($entry->{labels}) eq 'HASH' ? $entry->{labels} : {};
    return $labels;
}

sub save_node_labels {
    my ($node) = @_;
    return unless safe_segment($node);

    my $has_label_param = 0;
    for my $lang_code (@article_langs) {
        $has_label_param ||= exists $params{"node_label_$lang_code"};
    }
    return unless $has_label_param;

    $config->{nodes} ||= {};
    my $node_config = ref($config->{nodes}{$node}) eq 'HASH' ? $config->{nodes}{$node} : {};
    my $labels = ref($node_config->{labels}) eq 'HASH' ? $node_config->{labels} : {};
    for my $lang_code (@article_langs) {
        next unless exists $params{"node_label_$lang_code"};
        my $label = clean_text($params{"node_label_$lang_code"} || '');
        $labels->{$lang_code} = $label ne '' ? $label : $node;
    }
    $config->{nodes}{$node} = {
        %{$node_config},
        nav => exists($node_config->{nav}) ? $node_config->{nav} : JSON::PP::true,
        labels => $labels,
    };
    $store->write_json($config, 'dat', 'config.json');
}

sub collect_kiosk {
    my ($existing) = @_;
    my $has_kiosk_params = ($params{kiosk_enabled} || '') ne '';
    for my $number (1 .. 5) {
        $has_kiosk_params ||= exists $params{"kiosk_label_$number"} || exists $params{"kiosk_keyword_$number"};
    }
    return $existing->{kiosk} if !$has_kiosk_params && ref($existing->{kiosk}) eq 'HASH';

    my @items;
    for my $number (1 .. 5) {
        my $label = clean_text($params{"kiosk_label_$number"} || '');
        my $keyword = clean_text($params{"kiosk_keyword_$number"} || '');
        next if $label eq '' && $keyword eq '';
        push @items, {
            label   => $label ne '' ? $label : $keyword,
            keyword => $keyword ne '' ? $keyword : $label,
        };
    }

    return {
        enabled => ($params{kiosk_enabled} || '') eq '1' ? JSON::PP::true : JSON::PP::false,
        items   => \@items,
    };
}

sub clean_text {
    my ($value) = @_;
    $value = '' unless defined $value;
    $value =~ s/^\s+|\s+$//g;
    return $value;
}

sub normalize_lang {
    my ($lang) = @_;
    my %allowed = map { $_ => 1 } @article_langs;
    return $allowed{$lang} ? $lang : ($article_langs[0] || 'ja');
}

sub render_page {
    my ($title, $content) = @_;
    Mark6::Admin::render_page(
        title   => $title,
        active  => 'articles',
        root    => $ROOT,
        lang    => $lang,
        content => $content,
    );
}

sub h {
    return Mark6::CGI::escape_html(defined $_[0] ? $_[0] : '');
}

sub js_string {
    my ($value) = @_;
    $value = '' unless defined $value;
    $value =~ s/\\/\\\\/g;
    $value =~ s/'/\\'/g;
    $value =~ s/\r?\n/ /g;
    return Mark6::CGI::escape_html($value);
}

sub run_admin_action {
    my ($code) = @_;
    my $ok = eval {
        $code->();
        1;
    };
    return '' if $ok;

    my $error = $@ || 'Unknown error';
    chomp $error;
    return Mark6::CGI::escape_html($error);
}

sub public_article_url {
    my ($article) = @_;
    my $view_lang = $lang->code || Mark6::Article::default_lang($article, $config);
    my $path = Mark6::Article::public_path($article, $view_lang, $config);
    my $base = $config->{site}{base_url} || '';
    $base =~ s{/+\z}{};
    return $base eq '' ? $path : $base . $path;
}

sub parse_tags {
    my ($value) = @_;
    my @tags = grep { $_ ne '' } map {
        my $tag = $_;
        $tag =~ s/^\s+|\s+$//g;
        $tag;
    } split /,/, $value;
    return \@tags;
}

sub article_sort {
    my $a_order = article_sort_order($a);
    my $b_order = article_sort_order($b);
    my $a_has_order = defined($a->{sort_order}) && $a->{sort_order} =~ /\A[0-9]+\z/;
    my $b_has_order = defined($b->{sort_order}) && $b->{sort_order} =~ /\A[0-9]+\z/;
    return $a_order <=> $b_order if $a_has_order && $b_has_order && $a_order != $b_order;
    return -1 if $a_has_order && !$b_has_order;
    return 1 if !$a_has_order && $b_has_order;
    return ($b->{id} || 0) <=> ($a->{id} || 0);
}

sub article_sort_order {
    my ($article) = @_;
    return int($article->{sort_order}) if defined($article->{sort_order}) && $article->{sort_order} =~ /\A[0-9]+\z/;
    return '';
}

sub existing_sort_order {
    my ($article) = @_;
    return int($article->{sort_order}) if defined($article->{sort_order}) && $article->{sort_order} =~ /\A[0-9]+\z/;
    return JSON::PP::null;
}

sub article_initial_sort_order {
    my ($existing) = @_;
    return existing_sort_order($existing) if ($existing->{id} || '') ne '';

    my $min;
    for my $article (load_articles()) {
        my $order = article_sort_order($article);
        next if $order eq '';
        $min = $order if !defined($min) || $order < $min;
    }
    return defined($min) ? $min - 10 : 10;
}

sub normalize_status {
    my ($status) = @_;
    return $status eq 'published' ? 'published' : 'draft';
}

sub media_options {
    my ($selected) = @_;
    my @media = load_media();
    return '' unless @media;

    return join "\n", map {
        my $path = $_->{path} || '';
        my $label = $_->{original_filename} || $_->{filename} || $path;
        my $safe_path = Mark6::CGI::escape_html($path);
        my $safe_label = Mark6::CGI::escape_html($label);
        my $is_selected = $path eq $selected ? 'selected' : '';
        qq|<option value="$safe_path" $is_selected>$safe_label</option>|;
    } @media;
}

sub load_media {
    my $dir = "$ROOT/dat/media";
    return () unless -d $dir;

    opendir my $dh, $dir or die "Cannot open $dir: $!";
    my @files = grep { /\.json\z/ } readdir $dh;
    closedir $dh;

    my @media;
    for my $file (@files) {
        my $item = $store->read_json('dat', 'media', $file);
        next unless $item && ($item->{status} || 'active') eq 'active';
        push @media, $item;
    }

    return sort { ($b->{created_at} || '') cmp ($a->{created_at} || '') } @media;
}

sub safe_image_path {
    my ($value) = @_;
    return '' unless defined $value;
    return $value if $value =~ m{\Ahttps://[^\s<>"']+\z};
    return '' if $value =~ /\.\./;
    return $value =~ /\A[0-9A-Za-z_.\/-]+\z/ ? $value : '';
}

sub safe_segment {
    my ($value) = @_;
    $value = '' unless defined $value;
    $value =~ s/^\s+|\s+$//g;
    $value =~ s/[^0-9A-Za-z_-]+/-/g;
    $value =~ s/-+/-/g;
    $value =~ s/^-|-$//g;
    return $value;
}

sub iso_now {
    my @t = gmtime(time);
    return sprintf('%04d-%02d-%02dT%02d:%02d:%02dZ',
        $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0]);
}

sub format_date {
    my ($iso) = @_;
    return '' unless $iso =~ /\A(\d{4})-(\d{2})-(\d{2})/;
    return "$1-$2-$3";
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
