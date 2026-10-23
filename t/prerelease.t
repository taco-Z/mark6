use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Find qw(find);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);
use JSON::PP qw(encode_json decode_json);
use Mark6::DataStore;
use Mark6::Article;
use Mark6::Theme;
use Mark6::Extensions;
plan skip_all => 'Optional Memory extension is not installed' unless Mark6::Extensions::installed('memory');

my $root = tempdir(DIR => 't', CLEANUP => 1);
my $store = Mark6::DataStore->new(root => $root);
my $config = { site => { title => 'Test', node => 'articles' } };
$store->write_json($config, 'dat', 'config.json');
my $write_token = 'w' x 40;
my $read_token = 'r' x 40;
my $payload = { client_event_id => 'event-1', title => 'Private title', summary => 'Private summary', body => '<script>alert(1)</script>Private body' };
like(api(token => $write_token, method => 'POST', query => 'op=write', data => $payload), qr/Status: 404/, 'files and tokens alone do not activate API');
ok(!-d "$root/dat/articles", 'disabled API does not create article store');
$config->{extensions}{memory} = { enabled => JSON::PP::true, profile => 'sati' };
$store->write_json($config, 'dat', 'config.json');
like(api(), qr/Status: 401/, 'enabled API requires authentication');
like(api(token => $write_token, method => 'GET', query => 'op=article&id=x'), qr/Status: 401/, 'write token cannot read');
like(api(token => $read_token, method => 'POST', query => 'op=write', data => $payload), qr/Status: 401/, 'read token cannot write');
like(api(token => $write_token, method => 'POST', query => 'op=write', data => {%$payload, status => 'published'}), qr/Status: 400/, 'client cannot publish');
my $created = api(token => $write_token, method => 'POST', query => 'op=write', data => $payload);
like($created, qr/Status: 201/, 'memory stored');
my ($id) = $created =~ /"id":"([^"]+)"/;
ok($id, 'new article ID');
my $article = $store->read_json('dat', 'articles', "$id.json");
is($article->{status}, 'draft', 'same article store: draft');
is($article->{visibility}, 'private', 'private');
is($article->{review}{state}, 'pending', 'pending approval');
unlike($article->{body}, qr/<script>/, 'incoming HTML escaped');
ok(!Mark6::Article::is_public($article), 'not public');
like(api(token => $read_token, query => "op=article&id=$id"), qr/Private body/, 'authorized private retrieval');
like(api(token => $read_token, query => 'op=article&id=../../users'), qr/Status: 400/, 'traversal rejected');
$article->{status} = 'published';
ok(!Mark6::Article::is_public($article), 'status alone cannot publish');
$article->{review} = {state => 'approved', approved_by => 'admin'};
ok(!Mark6::Article::is_public($article), 'private overrides approval');
$article->{visibility} = 'public';
ok(Mark6::Article::is_public($article), 'approved public memory visible');
$store->write_json($article, 'dat', 'articles', "$id.json");
like(api(token => $write_token, method => 'POST', query => 'op=write', data => $payload), qr/duplicate/, 'retry does not overwrite reviewed article');
is($store->read_json('dat', 'articles', "$id.json")->{status}, 'published', 'retry preserves reviewed article');
ok(Mark6::Article::is_public({status => 'published', node => 'oita360'}), 'legacy OITA360 compatibility');
is(Mark6::Theme::css(undef), '', 'unconfigured theme leaves existing CSS unchanged');
my $theme = Mark6::Theme::normalize({preset => 'cee', accent => '</style><script>', width => '1);color:red', font => 'bad'});
is($theme->{accent}, '#1465a3', 'CSS injection rejected');
is($theme->{width}, 1080, 'invalid width rejected');
is($theme->{font}, 'sans', 'invalid font rejected');
# Stop and restart must neither change privacy nor destroy records.
$config->{extensions}{memory}{enabled} = JSON::PP::false;
$store->write_json($config, 'dat', 'config.json');
like(api(token => $read_token, query => "op=article&id=$id"), qr/Status: 404/, 'disabled API cannot read with a valid key');
like(api(token => $write_token, method => 'POST', query => 'op=write', data => $payload), qr/Status: 404/, 'disabled API cannot write with a valid key');
is($store->read_json('dat', 'articles', "$id.json")->{review}{state}, 'approved', 'disable preserves articles and review');
$config->{extensions}{memory}{enabled} = JSON::PP::true;
$store->write_json($config, 'dat', 'config.json');
like(api(script => 'public/memory.cgi', token => $read_token, query => "op=article&id=$id"), qr/Private body/, 'generic endpoint retrieves SATi profile after restart');

# A separate app copy without any extensions proves core does not depend on the add-on.
my $bare = tempdir(DIR => 't', CLEANUP => 1);
find({ no_chdir => 1, wanted => sub {
    return unless -f $_;
    my $target = "$bare/$_";
    $target =~ m{(.*)/[^/]+$}; make_path($1);
    copy($_, $target) or die "copy: $!";
}}, 'lib');
make_path("$bare/public");
copy("public/$_", "$bare/public/$_") or die "copy: $!" for qw(memory.cgi sati.cgi index.cgi);
for my $entry (qw(memory.cgi sati.cgi)) {
    like(api(script => "$bare/public/$entry", token => $read_token, query => "op=article&id=$id"), qr/Status: 404/, "missing extension disables $entry even with enabled flag");
}
my $pending = { %$article, id => 'pending', slug => 'pending', title => 'PRIVATE-SENTINEL',
    langs => {ja => {title => 'PRIVATE-SENTINEL', body => 'PRIVATE-SENTINEL'}},
    review => {state => 'pending'}, visibility => 'public', review_required => JSON::PP::true };
$store->write_json($pending, 'dat', 'articles', 'pending.json');
unlike(api(script => "$bare/public/index.cgi", query => 'order=focus&tar=pending'), qr/PRIVATE-SENTINEL/, 'core hides unapproved content without extension files');
like(api(script => "$bare/public/index.cgi", query => "order=focus&tar=$id"), qr/Private title/, 'approved article remains public without extension files');
unlike(api(script => "$bare/public/index.cgi", query => 'path=sitemap.xml'), qr/pending/, 'sitemap hides pending content without extension files');

# Generic profile does not need any SATi-specific credentials or identifiers.
$config->{extensions}{memory}{profile} = 'generic';
$store->write_json($config, 'dat', 'config.json');
like(api(token => $write_token, method => 'POST', query => 'op=write', data => {%$payload, client_event_id => 'generic-1'}), qr/"id":"memory-[a-f0-9]{64}"/, 'generic memory profile works');
like(api(token => $read_token, query => "op=article&id=$id"), qr/Status: 400/, 'generic profile cannot retrieve SATi namespace');
ok(!Mark6::Article::is_public({status => 'published', review => 'invalid'}), 'malformed review fails closed');
ok(!Mark6::Article::is_public({status => 'published', review_required => 1}), 'review-required articles stay private without approval metadata');
done_testing;

sub api {
    my (%args) = @_;
    local $ENV{MARK6_ROOT} = $root;
    local $ENV{SATI_WRITE_TOKEN} = $write_token;
    local $ENV{SATI_READ_TOKEN} = $read_token;
    local $ENV{MEMORY_WRITE_TOKEN} = $write_token;
    local $ENV{MEMORY_READ_TOKEN} = $read_token;
    local $ENV{HTTP_AUTHORIZATION} = $args{token} ? "Bearer $args{token}" : '';
    local $ENV{REQUEST_METHOD} = $args{method} || 'GET';
    local $ENV{QUERY_STRING} = $args{query} || '';
    local $ENV{CONTENT_TYPE} = 'application/json';
    my $body = $args{data} ? encode_json($args{data}) : '';
    local $ENV{CONTENT_LENGTH} = length $body;
    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, $^X, ($args{script} || 'public/sati.cgi'));
    print {$in} $body;
    close $in;
    my $result = do {local $/; <$out>};
    my $errors = do {local $/; <$err>};
    waitpid($pid, 0);
    die $errors if $?;
    return $result;
}
