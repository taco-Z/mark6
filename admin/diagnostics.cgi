#!/usr/bin/env perl

use strict;
use warnings;
use Cwd qw(abs_path getcwd);
use File::Basename qw(dirname);
use FindBin;
use IPC::Open3 qw(open3);
use Symbol qw(gensym);

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

render_diagnostics();

sub render_diagnostics {
    my $config = $store->read_json('dat', 'config.json') || {};
    my $ai = $config->{ai} || {};
    my $api_key_env = $ai->{api_key_env} || 'MARK6_OPENAI_API_KEY';
    my $api_key_file = $ai->{api_key_file} || default_api_key_file();
    my @candidate_names = env_candidates($api_key_env);
    my $env_rows = join "\n", map { env_row($_) } @candidate_names;
    my $related_env = related_env_summary();
    my $curl = curl_summary();
    my $feature_ai = $config->{features}{ai} ? 'enabled' : 'disabled';
    my $model = h($ai->{model} || 'gpt-5.2');
    my $provider = h($ai->{provider} || 'openai');
    my $safe_api_key_env = h($api_key_env);
    my $safe_api_key_file = h($api_key_file || '(none)');
    my $api_key_file_status = h(file_status($api_key_file));
    my $script_name = h($ENV{SCRIPT_NAME} || '');
    my $request_uri = h($ENV{REQUEST_URI} || '');
    my $redirect_status = h($ENV{REDIRECT_STATUS} || '');

    Mark6::Admin::render_page(
        title  => 'Diagnostics',
        active => 'settings',
        root   => $ROOT,
        lang   => $lang,
        content => <<"HTML",
<section class="article-detail">
  <a class="back-link" href="index.cgi">Dashboard</a>
  <h1>Diagnostics</h1>
  <p class="meta">Secrets are never printed on this page. Only presence is shown.</p>

  <fieldset>
    <legend>AI settings</legend>
    <div class="meta">AI feature: @{[h($feature_ai)]}</div>
    <div class="meta">Provider: $provider</div>
    <div class="meta">Model: $model</div>
    <div class="meta">Configured API key environment variable name: $safe_api_key_env</div>
    <div class="meta">API key file path: $safe_api_key_file</div>
    <div class="meta">API key file status: $api_key_file_status</div>
  </fieldset>

  <fieldset>
    <legend>Environment lookup</legend>
    <table>
      <tbody>
        $env_rows
      </tbody>
    </table>
    <div class="meta">$related_env</div>
  </fieldset>

  <fieldset>
    <legend>Runtime</legend>
    <div class="meta">curl: $curl</div>
    <div class="meta">SCRIPT_NAME: $script_name</div>
    <div class="meta">REQUEST_URI: $request_uri</div>
    <div class="meta">REDIRECT_STATUS: $redirect_status</div>
  </fieldset>
</section>
HTML
    );
}

sub env_candidates {
    my ($name) = @_;
    my @names;
    my $candidate = $name;
    for (1 .. 6) {
        push @names, $candidate;
        $candidate = "REDIRECT_$candidate";
    }
    return @names;
}

sub env_row {
    my ($name) = @_;
    my $present = defined $ENV{$name} && $ENV{$name} ne '' ? 'present' : 'missing';
    return '<tr><th>' . h($name) . '</th><td>' . h($present) . '</td></tr>';
}

sub related_env_summary {
    my @names = grep {
        /OPENAI/i || /MARK6_AI/i || /MARK6_OPENAI/i
    } sort keys %ENV;
    return 'Related environment variables visible: none' unless @names;
    return 'Related environment variables visible: ' . h(join(', ', @names));
}

sub curl_summary {
    my $err = gensym;
    my $ok = eval {
        my $pid = open3(my $in, my $out, $err, 'curl', '--version');
        close $in;
        my $output = do { local $/; <$out> };
        my $error = do { local $/; <$err> };
        waitpid($pid, 0);
        return ($? >> 8) == 0 ? first_line($output) : 'not available: ' . first_line($error);
    };
    return $ok if defined $ok && $ok ne '';
    return 'not available';
}

sub default_api_key_file {
    my $home = $ENV{HOME} || eval { (getpwuid($<))[7] } || '';
    return '' if $home eq '';
    return "$home/.mark6_openai_key";
}

sub file_status {
    my ($path) = @_;
    return 'not configured' unless defined $path && $path ne '';
    return 'missing' unless -e $path;
    return 'not a file' unless -f $path;
    return 'readable' if -r $path;
    return 'not readable';
}

sub first_line {
    my ($value) = @_;
    $value = '' unless defined $value;
    $value =~ s/\r?\n.*\z//s;
    return h($value || 'not available');
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
