#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use JSON::PP qw(decode_json encode_json);
use Digest::SHA qw(sha256_hex);
use POSIX qw(strftime);
BEGIN { unshift @INC, "$FindBin::Bin/../lib"; }
use Mark6::DataStore;
use Mark6::Root;

my $ROOT = $ENV{MARK6_ROOT} || Mark6::Root::default_root(findbin => $FindBin::Bin, script => $0, marker => 'dat/users.json');
my $store = Mark6::DataStore->new(root => $ROOT);
my $op = query_value('op') || '';
my $expected = $ENV{CEE_SECRET_TOKEN} || '';
my $auth = $ENV{HTTP_AUTHORIZATION} || '';
my ($token) = $auth =~ /\ABearer\s+(.+)\z/i;
unless ($expected ne '' && defined $token && sha256_hex($token) eq sha256_hex($expected)) {
    respond(401, { ok => JSON::PP::false, error => 'unauthorized' }); exit;
}
eval {
    if ($op eq 'write' && ($ENV{REQUEST_METHOD} || '') eq 'POST') {
        my $payload = request_json();
        my $event_id = safe_id($payload->{client_event_id} || '');
        die "client_event_id required" unless $event_id ne '';
        my @same = grep { ($_->{cee} || {})->{client_event_id} && $_->{cee}{client_event_id} eq $event_id } load_cee_articles();
        if (@same) { respond(200, { ok => JSON::PP::true, id => $same[0]{id}, duplicate => JSON::PP::true }); exit; }
        my $now = strftime('%Y-%m-%dT%H:%M:%SZ', gmtime);
        my $id = 'cee-' . $event_id;
        my $title = text($payload->{title}, 180) || 'CEE Memory';
        my $intro = text($payload->{description_html}, 600);
        my $body = text($payload->{body_html}, 10000);
        my $article = {
            id => $id, type => 'article', status => 'draft', default_lang => 'ja',
            title => $title, slug => $id, node => 'cee', tags => ['CEE-Memory'],
            image => '', intro => $intro, body => $body,
            langs => { ja => { title => $title, description => $intro, body => $body } },
            created_at => $now, updated_at => $now,
            cee => { source => text($payload->{source}, 32) || 'cee', client_event_id => $event_id },
        };
        $store->write_json($article, 'dat', 'articles', "$id.json");
        respond(201, { ok => JSON::PP::true, id => $id }); exit;
    }
    if ($op eq 'recent' && ($ENV{REQUEST_METHOD} || '') eq 'GET') {
        my $limit = query_value('limit') || 20; $limit = 20 unless $limit =~ /^\d+$/; $limit = 100 if $limit > 100;
        my @items = sort { ($b->{updated_at} || '') cmp ($a->{updated_at} || '') } load_cee_articles();
        @items = @items[0 .. $limit - 1] if @items > $limit;
        my @articles = map { { id => $_->{id}, title => $_->{title}, summary => $_->{intro}, updated_at => $_->{updated_at}, source => ($_->{cee} || {})->{source} } } @items;
        respond(200, { ok => JSON::PP::true, articles => \@articles }); exit;
    }
    if ($op eq 'article' && ($ENV{REQUEST_METHOD} || '') eq 'GET') {
        my $id = safe_id(query_value('id') || ''); die "invalid id" unless $id ne '';
        my $article = $store->read_json('dat', 'articles', "$id.json");
        die "not found" unless $article && ($article->{cee} || {})->{source};
        respond(200, { ok => JSON::PP::true, article => { id => $article->{id}, title => $article->{title}, summary => $article->{intro}, body_html => $article->{body}, updated_at => $article->{updated_at} } }); exit;
    }
    respond(404, { ok => JSON::PP::false, error => 'not_found' });
};
respond(400, { ok => JSON::PP::false, error => 'bad_request' }) if $@;

sub load_cee_articles {
    my $dir = "$ROOT/dat/articles"; return () unless -d $dir;
    opendir my $dh, $dir or return (); my @result;
    while (my ($name) = readdir $dh) {
        next unless $name =~ /\.json\z/;
        my $article = eval { $store->read_json('dat', 'articles', $name) };
        push @result, $article if $article && ($article->{cee} || {})->{source};
    }
    closedir $dh; return @result;
}
sub request_json {
    my $length = $ENV{CONTENT_LENGTH} || 0; die "invalid body" unless $length =~ /^\d+$/ && $length <= 20000;
    my $body = ''; read STDIN, $body, $length; my $value = decode_json($body || '{}');
    die "invalid JSON" unless ref $value eq 'HASH'; return $value;
}
sub query_value {
    my ($key) = @_; my $query = $ENV{QUERY_STRING} || '';
    for my $pair (split /&/, $query) {
        my ($k, $v) = split /=/, $pair, 2; next unless defined $k && $k eq $key;
        $v //= ''; $v =~ tr/+/ /; $v =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg; return $v;
    } return '';
}
sub safe_id { my ($value) = @_; $value //= ''; return $value =~ /\A[A-Za-z0-9_-]{1,96}\z/ ? $value : ''; }
sub text { my ($value, $limit) = @_; $value = '' unless defined $value; $value =~ s/[\x00-\x08\x0B\x0C\x0E-\x1F]//g; return substr("$value", 0, $limit); }
sub respond { my ($status, $data) = @_; print "Status: $status\r\nContent-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\n\r\n", encode_json($data); }
