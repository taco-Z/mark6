use strict;
use warnings;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);
use JSON::PP qw(encode_json decode_json);
use Mark6::DataStore;
use Mark6::Article;
use Mark6::CGI ();

my $root = tempdir(DIR => 't', CLEANUP => 1);
my $store = Mark6::DataStore->new(root => $root);
$store->write_json({site => {title => 'Test', node => 'articles', langs => ['ja','en']}}, 'dat', 'config.json');
my $secret = 'shared-secret-' . ('s' x 32);
my $payload = {client_event_id => 'session_01', title => 'CEE Memory: 岡城跡公園',
    description_html => 'PRIVATE-SENTINEL', body_html => '石垣<br>木々<script>alert(1)</script>', source => 'cee01', status => 'published'};

is(api(token => '')->{status}, 401, 'all operations require authentication');
is(api(token => 'wrong')->{status}, 401, 'wrong token rejected');
is(api(env => {CEE_SECRET_TOKEN => ''})->{status}, 401, 'unconfigured API fails closed');
is(api(env => {CEE_API_ENABLED => 'off'})->{status}, 404, 'optional API can be disabled');
ok(!-d "$root/dat/articles", 'denied requests do not create article store');
my $created = api(method => 'POST', op => 'write', data => $payload);
is($created->{status}, 201, 'legacy CEE01 payload accepted');
is($created->{json}{id}, 'cee-session_01', 'stable legacy article ID');
like($created->{raw}, qr/Cache-Control: no-store/, 'private responses are not cached');
like($created->{raw}, qr/X-Content-Type-Options: nosniff/, 'JSON response is not sniffed');
my $article = $store->read_json('dat', 'articles', 'cee-session_01.json');
is($article->{title}, $payload->{title}, 'Japanese title round trips');
is($article->{status}, 'draft', 'client cannot publish');
is($article->{visibility}, 'private', 'private on arrival');
is($article->{review}{state}, 'pending', 'pending manual review');
ok(Mark6::Article::requires_review($article), 'existing administrator review workflow applies');
is($article->{cee}{source}, 'cee01', 'existing CEE metadata retained');
like($article->{body}, qr/<br>/, 'CEE01 line break markup preserved');
unlike($article->{body}, qr/<script>/, 'script markup escaped before admin preview');
like($article->{body}, qr/&lt;script&gt;/, 'escaped script remains readable as text');
$article->{status} = 'published';
ok(!Mark6::Article::is_public($article), 'status alone cannot disclose memory');
# Deliberately simulate an accidental status/visibility change, preserving pending review.
$article->{visibility} = 'public';
$store->write_json($article, 'dat', 'articles', 'cee-session_01.json');
ok(!Mark6::Article::is_public($article), 'pending review still blocks public visibility');
for my $path ('/ja/', '/ja/cee/', '/ja/cee/cee-session_01/', '/rss.xml', '/sitemap.xml', '/api/articles') {
    my $result = api(script => 'public/index.cgi', op => '', extra_query => 'path=' . Mark6::CGI::url_encode($path));
    unlike($result->{raw}, qr/PRIVATE-SENTINEL/, "unapproved CEE hidden at $path");
}
unlike(api(script => 'public/index.cgi', op => '', extra_query => 'order=focus&tar=cee-session_01')->{raw}, qr/PRIVATE-SENTINEL/, 'legacy direct ID hides unapproved memory');
unlike(api(script => 'public/index.cgi', op => '', extra_query => 'q=PRIVATE-SENTINEL')->{raw}, qr/PRIVATE-SENTINEL<\//, 'search does not expose private content');

my $detail = api(op => 'article', extra_query => 'id=cee-session_01');
is($detail->{status}, 200, 'authenticated detail read');
is($detail->{json}{article}{title}, $payload->{title}, 'client detail response shape retained');
my $recent = api(op => 'recent');
is($recent->{status}, 200, 'authenticated recent read');
is($recent->{json}{articles}[0]{summary}, 'PRIVATE-SENTINEL', 'client summary shape retained');
ok(!exists $recent->{json}{articles}[0]{body_html}, 'recent list excludes body');
$article->{review} = {state => 'approved', approved_by => 'admin'};
$store->write_json($article, 'dat', 'articles', 'cee-session_01.json');
my $before = $article;
my $duplicate = api(method => 'POST', op => 'write', data => {%$payload, body_html => 'overwrite attempt'});
is($duplicate->{status}, 200, 'retry succeeds');
ok($duplicate->{json}{duplicate}, 'retry marked duplicate');
is_deeply($store->read_json('dat', 'articles', 'cee-session_01.json'), $before, 'retry preserves administrator edits and approval');

$store->write_json({id => 'cee-other', status => 'draft', title => 'OTHER-SENTINEL'}, 'dat', 'articles', 'cee-other.json');
is(api(op => 'article', extra_query => 'id=cee-other')->{status}, 404, 'non-CEE article cannot be read');
is(api(op => 'article', extra_query => 'id=cee-missing')->{status}, 404, 'missing article returns 404');
is(api(op => 'article', extra_query => 'id=../../users')->{status}, 400, 'path traversal rejected');
is(api(method => 'POST', op => 'write', data => {%$payload, client_event_id => 'other'})->{status}, 400, 'non-CEE ID collision rejected');
is($store->read_json('dat', 'articles', 'cee-other.json')->{title}, 'OTHER-SENTINEL', 'collision preserves unrelated article');
for my $limit ('0','-1','bad','1000000') {
    is(api(op => 'recent', extra_query => "limit=$limit")->{status}, 400, "invalid limit $limit rejected");
}
is(api(op => 'recent', extra_query => 'limit=101')->{status}, 200, 'large valid limit capped');
is(api(op => 'update', method => 'POST', data => $payload)->{status}, 404, 'update remains explicitly unsupported');
is(api(op => 'write', method => 'GET')->{status}, 404, 'GET cannot write');
is(api(op => 'recent', method => 'POST', data => $payload)->{status}, 404, 'POST cannot read');
for my $case (
    {raw_body => '{'}, {raw_body => '[]'}, {content_type => 'text/plain'},
    {length => 20001}, {length => 19999},
    {data => {%$payload, client_event_id => '../x'}},
    {data => {%$payload, body_html => ''}}, {data => {%$payload, title => {bad => 1}}},
    {data => {%$payload, title => 'x' x 181}},
    {data => {%$payload, review => {state => 'approved'}}},
    {data => {%$payload, visibility => 'public'}},
    {data => {%$payload, image => 'https://example.invalid/private.jpg', client_event_id => 'no-image'}}
) {
    my $result = api(method => 'POST', op => 'write', data => $payload, %$case);
    if (($case->{data} || {})->{client_event_id} && $case->{data}{client_event_id} eq 'no-image') {
        is($result->{status}, 201, 'legacy image input ignored');
        is($store->read_json('dat', 'articles', 'cee-no-image.json')->{image}, '', 'image is never stored');
    } else { is($result->{status}, 400, 'invalid input rejected'); }
}
my %keys = (CEE_WRITE_TOKEN => 'w' x 40, CEE_READ_TOKEN => 'r' x 40);
is(api(token => $secret, env => \%keys)->{status}, 401, 'dedicated read key overrides shared token');
is(api(token => 'w' x 40, env => \%keys)->{status}, 401, 'write key cannot read');
is(api(token => 'r' x 40, env => \%keys)->{status}, 200, 'dedicated read key works');
is(api(token => 'r' x 40, env => \%keys, op => 'write', method => 'POST', data => $payload)->{status}, 401, 'read key cannot write');
is(api(token => 'w' x 40, env => \%keys, op => 'write', method => 'POST', data => $payload)->{status}, 200, 'dedicated write key works');
is(api(token => '', env => {HTTP_AUTHORIZATION => '', REDIRECT_HTTP_AUTHORIZATION => "Bearer $secret", CEE_SECRET_TOKEN => '', REDIRECT_CEE_SECRET_TOKEN => $secret})->{status}, 200, 'Apache redirected credentials work');
my $long = 'x' x 96;
is(api(op => 'write', method => 'POST', data => {%$payload, client_event_id => $long})->{status}, 201, '96 character event ID accepted');
is(api(op => 'article', extra_query => 'id=cee-' . $long)->{status}, 200, 'longest created ID can be retrieved');
# Concurrent retries must create one record without replacing it.
my @jobs = map { start_api(method => 'POST', op => 'write', data => {%$payload, client_event_id => 'concurrent'}) } 1..4;
my @responses = map { finish_api($_) } @jobs;
is(scalar(grep {$_->{status} == 201} @responses), 1, 'exactly one concurrent writer creates record');
is(scalar(grep {$_->{status} == 200 && $_->{json}{duplicate}} @responses), 3, 'other concurrent writers return duplicate');
my $rules = do {open my $fh, '<', '.htaccess' or die $!; local $/; <$fh>};
like($rules, qr/RewriteRule \^cee\/\(write\|recent\|article\|update\)\$ public\/cee\.cgi\?op=\$1/, 'documented URLs wired before catch-all');
is(api(env => {CEE_API_ENABLED => '0'})->{status}, 404, 'disabled after use');
ok($store->read_json('dat', 'articles', 'cee-session_01.json'), 'disable preserves records');
is(api()->{status}, 200, 'reenabling restores authenticated access');
done_testing;

sub api { return finish_api(start_api(@_)); }
sub start_api {
    my (%args) = @_;
    local %ENV = %ENV;
    delete @ENV{grep {/\A(?:REDIRECT_)*(?:CEE_|HTTP_AUTHORIZATION)/} keys %ENV};
    $ENV{MARK6_ROOT} = $root;
    $ENV{CEE_SECRET_TOKEN} = $secret;
    $ENV{HTTP_AUTHORIZATION} = 'Bearer ' . (exists($args{token}) ? $args{token} : $secret);
    $ENV{REQUEST_METHOD} = $args{method} || 'GET';
    $ENV{QUERY_STRING} = 'op=' . ($args{op} // 'recent') . '&' . ($args{extra_query} || '');
    $ENV{CONTENT_TYPE} = $args{content_type} || 'application/json';
    my $body = exists($args{raw_body}) ? $args{raw_body} : $args{data} ? encode_json($args{data}) : '';
    $ENV{CONTENT_LENGTH} = $args{length} // length($body);
    @ENV{keys %{$args{env} || {}}} = values %{$args{env} || {}};
    my $err = gensym;
    my $input = File::Temp->new(DIR => 't', UNLINK => 1);
    binmode $input; print {$input} $body; seek($input, 0, 0) or die $!;
    # A real input file makes premature EOF deterministic on Windows too.
    my $pid = open3('<&' . fileno($input), my $out, $err, $^X, ($args{script} || 'public/cee.cgi'));
    binmode $out; binmode $err;
    return [$pid, $out, $err, $input];
}
sub finish_api {
    my ($job) = @_;
    my ($pid, $out, $err) = @$job;
    my $result = do {local $/; <$out>} // '';
    my $errors = do {local $/; <$err>} // '';
    close $out; close $err;
    waitpid($pid, 0);
    die $errors if $?;
    die $errors if $errors =~ /(?:Wide character|malformed|uninitialized)/i;
    my ($status) = $result =~ /Status: (\d+)/;
    my (undef, $body) = split /\r?\n\r?\n/, $result, 2;
    return {status => $status || 200, raw => $result, json => eval {decode_json($body)} || {}};
}
