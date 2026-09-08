#!/usr/bin/env perl

use strict;
use warnings;
use utf8;
use Cwd qw(abs_path getcwd);
use Encode qw(encode);
use File::Basename qw(dirname);
use File::Spec;
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

use Mark6::Admin;
use Mark6::Auth;
use Mark6::CGI qw();
use Mark6::Lang;
use Mark6::QualityReport;
use Mark6::Root;

my $ROOT = $ENV{MARK6_ROOT} || Mark6::Root::default_root(findbin => $FindBin::Bin, script => $0, marker => 'dat/users.json');
my $auth = Mark6::Auth->new(root => $ROOT);
my $lang = Mark6::Lang->new(root => $ROOT);
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

my %params = Mark6::CGI::request_params();
my $profile = valid_profile($params{profile} || auto_profile());
my $node = safe_node(exists $params{node} ? $params{node} : auto_node($profile));
my $format = $params{format} || '';

if (($params{command} || '') eq 'generate') {
    generate_report($profile, $node);
    Mark6::CGI::redirect('quality.cgi?profile=' . Mark6::CGI::url_encode($profile) . '&node=' . Mark6::CGI::url_encode($node) . '&generated=1');
    exit;
}

if ($format eq 'csv') {
    generate_report($profile, $node) unless -e csv_path($profile);
    print_file(csv_path($profile), 'text/csv; charset=UTF-8', "content_check_$profile.csv");
    exit;
}

if ($format eq 'md') {
    generate_report($profile, $node) unless -e markdown_path($profile);
    print_file(markdown_path($profile), 'text/markdown; charset=UTF-8', "content_check_$profile.md");
    exit;
}

render_quality_page($profile, $node);

sub render_quality_page {
    my ($profile, $node) = @_;
    my $markdown = markdown_path($profile);
    my $csv = csv_path($profile);
    my $has_report = -e $markdown;
    my %label = quality_labels();
    my $generated = $params{generated} ? '<p class="notice">' . $label{generated} . '</p>' : '';
    my $summary = $has_report ? report_summary_html($markdown) : '<p class="empty">' . $label{no_report} . '</p>';
    my $preview = $has_report ? report_preview_html($markdown) : '';
    my $safe_profile = h($profile);
    my $safe_node = h($node);
    my $csv_link = h("quality.cgi?profile=$profile&node=" . Mark6::CGI::url_encode($node) . "&format=csv");
    my $md_link = h("quality.cgi?profile=$profile&node=" . Mark6::CGI::url_encode($node) . "&format=md");
    my $csv_status = -e $csv ? h(file_size($csv) . ' bytes') : $label{not_generated};
    my $node_display = $safe_node || $label{all_nodes};
    my $target = h(join ' / ', grep { $_ ne '' } ($label{target_auto}, $safe_profile, $node_display));

    Mark6::Admin::render_page(
        title  => $label{title_text},
        active => 'quality',
        root   => $ROOT,
        lang   => $lang,
        content => <<"HTML",
<section class="article-detail">
  <a class="back-link" href="index.cgi">$label{dashboard}</a>
  <h1>$label{title}</h1>
  <p class="meta">$label{description}</p>
  $generated

  <form class="admin-form" method="post" action="quality.cgi">
    <fieldset>
      <legend>$label{run_check}</legend>
      <p class="meta">$target</p>
      <input type="hidden" name="command" value="generate">
      <input type="hidden" name="profile" value="$safe_profile">
      <input type="hidden" name="node" value="$safe_node">
      <button type="submit">$label{run_check}</button>
    </fieldset>
  </form>

  <section class="dashboard-stats">
    <h2>$label{current_check}</h2>
    <div class="meta">$label{csv}: $csv_status</div>
    <div class="admin-toolbar">
      <a class="button secondary" href="$csv_link">$label{view_csv}</a>
      <a class="button secondary" href="$md_link">$label{view_markdown}</a>
    </div>
    $summary
  </section>

  <section class="dashboard-stats">
    <h2>$label{preview}</h2>
    $preview
  </section>
</section>
HTML
    );
}

sub generate_report {
    my ($profile, $node) = @_;
    my $report = Mark6::QualityReport->new(root => $ROOT, profile => $profile, node => $node)->generate;
    Mark6::QualityReport::write_markdown($report, markdown_path($profile));
    Mark6::QualityReport::write_csv($report, csv_path($profile));
}

sub report_summary_html {
    my ($path) = @_;
    my $text = read_text($path);
    my %label = quality_labels();
    my @items;
    for my $priority (qw(P0 P1 P2 P3 INFO OK)) {
        if ($text =~ /^- \Q$priority\E: (\d+)/m) {
            push @items, qq|<div class="stat"><span>$priority</span><strong>@{[h($1)]}</strong></div>|;
        }
    }
    my @statuses;
    for my $status (qw(BLOCK FIX REVIEW OK)) {
        if ($text =~ /^- \Q$status\E: (\d+)/m) {
            push @statuses, qq|<div class="stat"><span>$status</span><strong>@{[h($1)]}</strong></div>|;
        }
    }
    my %summary_label = quality_labels();
    return '<h3>' . $summary_label{risk} . '</h3><div class="stats-grid">' . join('', @items) . '</div><h3>' . $summary_label{status} . '</h3><div class="stats-grid">' . join('', @statuses) . '</div>' if @items || @statuses;
    return '<p class="empty">' . $label{no_summary} . '</p>';
}

sub report_preview_html {
    my ($path) = @_;
    my $text = read_text($path);
    my %label = quality_labels();
    my @sections = $text =~ /^(### \[[\s\S]*?)(?=^### |\z)/mg;
    @sections = @sections[0 .. 9] if @sections > 10;
    return '<p class="empty">' . $label{no_findings} . '</p>' unless @sections;

    my $html = '<div class="quality-preview">';
    for my $section (@sections) {
        my ($heading) = $section =~ /^### (.+)$/m;
        my ($file) = $section =~ /^- file: `([^`]+)`/m;
        my ($issues) = $section =~ /^- issues: (.+)$/m;
        $html .= '<article class="admin-row quality-row"><div>';
        $html .= '<strong>' . h($heading || $label{finding}) . '</strong>';
        $html .= '<div class="meta">' . h($file || '') . '</div>';
        $html .= '<div>' . h($issues || '') . '</div>';
        $html .= '</div></article>';
    }
    $html .= '</div>';
    return $html;
}

sub print_file {
    my ($path, $content_type, $download_name) = @_;
    my $body = -e $path ? read_text($path) : '';
    print "Content-Type: $content_type\n";
    print "Content-Disposition: inline; filename=\"$download_name\"\n\n";
    print encode('UTF-8', $body);
}

sub markdown_path {
    my ($profile) = @_;
    return Mark6::QualityReport::default_markdown_path($ROOT, $profile);
}

sub csv_path {
    my ($profile) = @_;
    return Mark6::QualityReport::default_csv_path($ROOT, $profile);
}

sub valid_profile {
    my ($profile) = @_;
    $profile = 'regional_media' if $profile eq 'oita360';
    return $profile if $profile =~ /\A[a-z][a-z0-9_-]*\z/i;
    return 'default';
}

sub auto_profile {
    my $config = read_json_file(File::Spec->catfile($ROOT, 'dat', 'config.json')) || {};
    my $checker = ref($config->{content_checker}) eq 'HASH' ? $config->{content_checker} : {};
    return valid_profile($checker->{profile} || 'default');
}

sub auto_node {
    my ($profile) = @_;
    my $config = read_json_file(File::Spec->catfile($ROOT, 'dat', 'config.json')) || {};
    my $site = ref($config->{site}) eq 'HASH' ? $config->{site} : {};
    my $node = $site->{node} || '';
    return article_node_count($node) ? $node : '';
}

sub article_node_count {
    my ($node) = @_;
    my $dir = File::Spec->catdir($ROOT, 'dat', 'articles');
    return 0 unless -d $dir;
    opendir my $dh, $dir or return 0;
    my @files = grep { /\.json\z/ } readdir $dh;
    closedir $dh;

    my $count = 0;
    for my $file (@files) {
        my $article = read_json_file(File::Spec->catfile($dir, $file)) || next;
        $count++ if lc($article->{node} || '') eq lc($node || '');
    }
    return $count;
}

sub read_json_file {
    my ($path) = @_;
    open my $fh, '<:raw', $path or return undef;
    local $/;
    my $raw = <$fh>;
    close $fh;
    return eval { JSON::PP->new->utf8->decode($raw) } || undef;
}

sub safe_node {
    my ($node) = @_;
    $node = '' unless defined $node;
    $node =~ s/^\s+|\s+$//g;
    return $node =~ /\A[0-9A-Za-z_-]*\z/ ? $node : '';
}

sub read_text {
    my ($path) = @_;
    open my $fh, '<:encoding(UTF-8)', $path or return '';
    local $/;
    return <$fh>;
}

sub file_size {
    my ($path) = @_;
    return -e $path ? (-s $path || 0) : 0;
}

sub h {
    return Mark6::CGI::escape_html($_[0] || '');
}

sub quality_labels {
    return (
        title_text       => $lang->t('admin.quality.title', 'Content Check'),
        title            => h($lang->t('admin.quality.title', 'Content Check')),
        dashboard        => h($lang->t('admin.common.dashboard', 'Dashboard')),
        description      => h($lang->t('admin.quality.description', 'Check article JSON health from the server. MARK6 chooses the basic checks automatically.')),
        generated        => h($lang->t('admin.quality.generated', 'Content check generated.')),
        no_report        => h($lang->t('admin.quality.no_report', 'No report yet.')),
        not_generated    => h($lang->t('admin.quality.not_generated', 'not generated')),
        run_check        => h($lang->t('admin.quality.run_check', 'Run check')),
        target_auto      => h($lang->t('admin.quality.target_auto', 'Target: automatic')),
        current_check    => h($lang->t('admin.quality.current_check', 'Current check')),
        node             => h($lang->t('admin.quality.node', 'Node')),
        all_nodes        => h($lang->t('admin.quality.all_nodes', '(all)')),
        csv              => h($lang->t('admin.quality.csv', 'CSV')),
        view_csv         => h($lang->t('admin.quality.view_csv', 'View CSV')),
        view_markdown    => h($lang->t('admin.quality.view_markdown', 'View Markdown')),
        preview          => h($lang->t('admin.quality.preview', 'Preview')),
        no_summary       => h($lang->t('admin.quality.no_summary', 'No summary found.')),
        no_findings      => h($lang->t('admin.quality.no_findings', 'No findings.')),
        finding          => h($lang->t('admin.quality.finding', 'Finding')),
        risk             => h($lang->t('admin.quality.risk', 'Risk')),
        status           => h($lang->t('admin.quality.status', 'Status')),
    );
}
