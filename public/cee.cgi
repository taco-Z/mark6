#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use JSON::PP qw(decode_json encode_json);
use Digest::SHA qw(sha256_hex);
use POSIX qw(strftime);
use File::Path qw(make_path);
use Fcntl qw(:flock);
BEGIN { unshift @INC, "$FindBin::Bin/../lib"; }
use Mark6::CGI ();
use Mark6::DataStore;
use Mark6::Root;

my $ROOT = $ENV{MARK6_ROOT} || Mark6::Root::default_root(findbin => $FindBin::Bin, script => $0, marker => 'dat/users.json');
my $store = Mark6::DataStore->new(root => $ROOT);
my %query = Mark6::CGI::query_params($ENV{QUERY_STRING} || '');
my $op = $query{op} || '';
my $method = $ENV{REQUEST_METHOD} || 'GET';
if (server_env('CEE_API_ENABLED') =~ /\A(?:0|false|off)\z/i) {
    respond(404, { ok => JSON::PP::false, error => 'not_found' }); exit;
}
# Dedicated keys override the legacy shared key for their operation.
my $expected = server_env($op eq 'write' ? 'CEE_WRITE_TOKEN' : 'CEE_READ_TOKEN') || server_env('CEE_SECRET_TOKEN');
my ($token) = server_env('HTTP_AUTHORIZATION') =~ /\ABearer\s+([^\s]+)\z/i;
unless ($expected ne '' && defined($token) && constant_equal(sha256_hex($token), sha256_hex($expected))) {
    respond(401, { ok => JSON::PP::false, error => 'unauthorized' }); exit;
}
my $handled = eval {
    if ($op eq 'write' && $method eq 'POST') {
        my $payload = request_json();
        for my $key (keys %$payload) {
            die 'unknown field' unless $key =~ /\A(?:client_event_id|title|description_html|body_html|source|status|image)\z/;
        }
        my $event_id = safe_id($payload->{client_event_id});
        die 'event required' unless $event_id ne '';
        my $title = text($payload->{title}, 180) || 'CEE Memory';
        my $intro = safe_html(text($payload->{description_html}, 600));
        my $body_text = text($payload->{body_html}, 10000);
        die 'body required' unless $body_text =~ /\S/;
        my $body = safe_html($body_text);
        my $source = text($payload->{source}, 32) || 'cee';
        my $id = 'cee-' . $event_id;
        # Serialize retries before checking the deterministic article ID.
        make_path("$ROOT/dat");
        open my $lock, '>>', "$ROOT/dat/cee-write.lock" or die 'lock';
        flock($lock, LOCK_EX) or die 'lock';
        my $existing = $store->read_json('dat', 'articles', "$id.json");
        if ($existing) {
            die 'id conflict' unless is_cee($existing) && ($existing->{cee}{client_event_id} || '') eq $event_id;
            respond(200, { ok => JSON::PP::true, id => $id, duplicate => JSON::PP::true });
        } else {
            my $now = strftime('%Y-%m-%dT%H:%M:%SZ', gmtime);
            my $article = {
                id => $id, type => 'article', status => 'draft', default_lang => 'ja',
                visibility => 'private', review_required => JSON::PP::true, review => { state => 'pending' },
                title => $title, slug => $id, node => 'cee', tags => ['CEE-Memory'],
                image => '', intro => $intro, body => $body,
                langs => { ja => { title => $title, description => $intro, body => $body } },
                created_at => $now, updated_at => $now,
                cee => { source => $source, client_event_id => $event_id },
            };
            $store->write_json($article, 'dat', 'articles', "$id.json");
            respond(201, { ok => JSON::PP::true, id => $id });
        }
        close $lock;
    }
    elsif ($op eq 'recent' && $method eq 'GET') {
        my $limit = $query{limit} // 20;
        die 'limit' unless $limit =~ /\A\d{1,6}\z/ && $limit >= 1;
        $limit = 100 if $limit > 100;
        my @items = sort { ($b->{updated_at} || '') cmp ($a->{updated_at} || '') || $a->{id} cmp $b->{id} } load_cee_articles();
        splice(@items, $limit) if @items > $limit;
        my @articles = map { { id => $_->{id}, title => $_->{title}, summary => $_->{intro}, updated_at => $_->{updated_at}, source => $_->{cee}{source} } } @items;
        respond(200, { ok => JSON::PP::true, articles => \@articles });
    }
    elsif ($op eq 'article' && $method eq 'GET') {
        my $id = safe_id($query{id}, 100);
        die 'invalid id' unless $id =~ /\Acee-[A-Za-z0-9_-]{1,96}\z/;
        my $article = $store->read_json('dat', 'articles', "$id.json");
        if (is_cee($article)) {
            respond(200, { ok => JSON::PP::true, article => { id => $article->{id}, title => $article->{title}, summary => $article->{intro}, body_html => $article->{body}, updated_at => $article->{updated_at} } });
        } else { respond(404, { ok => JSON::PP::false, error => 'not_found' }); }
    }
    else { respond(404, { ok => JSON::PP::false, error => 'not_found' }); }
    1;
};
respond(400, { ok => JSON::PP::false, error => 'bad_request' }) unless $handled;

sub is_cee {
    my ($article) = @_;
    return ref($article) eq 'HASH' && ref($article->{cee}) eq 'HASH' && ($article->{cee}{source} || '') ne '';
}
sub load_cee_articles {
    my $dir = "$ROOT/dat/articles"; return () unless -d $dir;
    opendir my $dh, $dir or die 'article directory';
    my @result;
    while (my $name = readdir $dh) {
        next unless $name =~ /\Acee-[A-Za-z0-9_-]{1,96}\.json\z/;
        my $article = eval { $store->read_json('dat', 'articles', $name) };
        push @result, $article if is_cee($article);
    }
    closedir $dh; return @result;
}
sub request_json {
    die 'content type' unless ($ENV{CONTENT_TYPE} || '') =~ m{\Aapplication/json(?:\s*;|\z)}i;
    my $length = $ENV{CONTENT_LENGTH} || '';
    die 'invalid body' unless $length =~ /\A\d{1,6}\z/ && $length > 0 && $length <= 20000;
    binmode STDIN;
    my $body = '';
    while (length($body) < $length) {
        my $n = read(STDIN, my $chunk, $length - length($body));
        die 'short body' unless $n;
        $body .= $chunk;
    }
    my $value = decode_json($body);
    die 'invalid JSON' unless ref($value) eq 'HASH'; return $value;
}
sub safe_id {
    my ($value, $limit) = @_; $limit ||= 96;
    return '' unless defined($value) && !ref($value);
    return $value =~ /\A[A-Za-z0-9_-]{1,$limit}\z/ ? $value : '';
}
sub text {
    my ($value, $limit) = @_; return '' unless defined $value;
    die 'text' if ref($value) || length($value) > $limit;
    $value =~ s/[\x00-\x08\x0B\x0C\x0E-\x1F]//g; return "$value";
}
sub safe_html {
    # The CEE01 client sends line breaks as <br>. Preserve only that markup;
    # escape all other input before it reaches admin previews or public pages.
    my $value = Mark6::CGI::escape_html($_[0]);
    $value =~ s/&lt;br\s*\/?&gt;/<br>/gi;
    return $value;
}
sub server_env {
    my ($name) = @_;
    for my $prefix ('', 'REDIRECT_', 'REDIRECT_REDIRECT_') {
        return $ENV{$prefix . $name} if defined($ENV{$prefix . $name}) && $ENV{$prefix . $name} ne '';
    }
    return '';
}
sub constant_equal {
    my ($a, $b) = @_; return 0 unless length($a) == length($b);
    my $diff = 0;
    $diff |= ord(substr($a, $_, 1)) ^ ord(substr($b, $_, 1)) for 0 .. length($a) - 1;
    return $diff == 0;
}
sub respond {
    my ($status, $data) = @_;
    binmode STDOUT;
    print "Status: $status\r\nContent-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n\r\n", encode_json($data);
}
