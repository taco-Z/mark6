package Mark6::Extension::Memory;
use strict;
use warnings;
use JSON::PP qw(decode_json encode_json);
use Digest::SHA qw(sha256_hex);
use POSIX qw(strftime);
use File::Path qw(make_path);
use Fcntl qw(:flock);
use Mark6::CGI ();
use Mark6::DataStore;

sub profile {
    my ($config) = @_;
    my $name = ($config->{extensions}{memory} || {})->{profile} || 'generic';
    return $name eq 'sati'
        ? { source => 'sati', node => 'sati-memory', prefix => 'sati', write_env => 'SATI_WRITE_TOKEN', read_env => 'SATI_READ_TOKEN' }
        : { source => 'memory', node => 'memory', prefix => 'memory', write_env => 'MEMORY_WRITE_TOKEN', read_env => 'MEMORY_READ_TOKEN' };
}
sub run {
    my (%args) = @_;
    my $root = $args{root};
    my $profile = profile($args{config});
    my $store = Mark6::DataStore->new(root => $root);
    my %query = Mark6::CGI::query_params($ENV{QUERY_STRING} || '');
    my $op = $query{op} || '';
    my $method = $ENV{REQUEST_METHOD} || 'GET';
    # Disabled unless the server explicitly provisions the relevant credential.
    my $expected = $ENV{$op eq 'write' ? $profile->{write_env} : $profile->{read_env}} || '';
    my ($token) = ($ENV{HTTP_AUTHORIZATION} || '') =~ /\ABearer ([^\s]+)\z/;
    unless (length($expected) >= 32 && defined($token) && constant_equal(sha256_hex($token), sha256_hex($expected))) {
        respond(401, { error => 'unauthorized' }); return;
    }
    eval {
        if ($op eq 'write' && $method eq 'POST') {
            die 'content type' unless ($ENV{CONTENT_TYPE} || '') =~ m{\Aapplication/json(?:\s*;|\z)}i;
            my $length = $ENV{CONTENT_LENGTH} || '';
            die 'length' unless $length =~ /\A\d+\z/ && $length > 0 && $length <= 20000;
            my $raw = '';
            while (length($raw) < $length) {
                my $n = read(STDIN, my $chunk, $length - length($raw));
                die 'short body' unless $n;
                $raw .= $chunk;
            }
            my $payload = decode_json($raw);
            die 'object' unless ref($payload) eq 'HASH';
            # Explicit allowlist: clients cannot set status, node, visibility or approval.
            for my $key (keys %$payload) { die 'unknown field' unless $key =~ /\A(?:client_event_id|title|summary|body)\z/; }
            my $event = $payload->{client_event_id};
            die 'event' unless defined($event) && !ref($event) && $event =~ /\A[A-Za-z0-9_-]{1,96}\z/;
            for my $key (qw(title summary body)) {
                die 'text' unless defined($payload->{$key}) && !ref($payload->{$key});
            }
            die 'limits' unless length($payload->{title}) <= 180 && length($payload->{summary}) <= 600 && length($payload->{body}) <= 10000 && $payload->{body} =~ /\S/;
            my $id = $profile->{prefix} . '-' . sha256_hex($event);
            make_path("$root/dat");
            open my $lock, '>>', "$root/dat/memory-write.lock" or die 'lock';
            flock($lock, LOCK_EX) or die 'lock';
            my $existing = $store->read_json('dat', 'articles', "$id.json");
            if ($existing) { respond(200, { id => $id, duplicate => JSON::PP::true }); }
            else {
                my $now = strftime('%Y-%m-%dT%H:%M:%SZ', gmtime);
                my $title = $payload->{title};
                # Incoming memory is plain text. Escaping prevents stored script execution in admin previews.
                my $summary = Mark6::CGI::escape_html($payload->{summary});
                my $body = '<p>' . Mark6::CGI::escape_html($payload->{body}) . '</p>';
                my $article = {
                    id => $id, slug => $id, type => 'article', node => $profile->{node},
                    status => 'draft', visibility => 'private', review => { state => 'pending' },
                    review_required => JSON::PP::true, memory => { source => $profile->{source} }, default_lang => 'ja',
                    title => $title, intro => $summary, body => $body,
                    langs => { ja => { title => $title, description => $summary, body => $body } },
                    created_at => $now, updated_at => $now,
                };
                $store->write_json($article, 'dat', 'articles', "$id.json");
                respond(201, { id => $id });
            }
            close $lock;
        }
        elsif ($op eq 'article' && $method eq 'GET') {
            my $id = $query{id} || '';
            die 'id' unless $id =~ /\A\Q$profile->{prefix}\E-[a-f0-9]{64}\z/;
            my $article = $store->read_json('dat', 'articles', "$id.json");
            if ($article && ($article->{memory} || {})->{source} && $article->{memory}{source} eq $profile->{source}) {
                respond(200, { article => { map { $_ => $article->{$_} } qw(id title intro body status updated_at) } });
            } else { respond(404, { error => 'not_found' }); }
        }
        else { respond(404, { error => 'not_found' }); }
    };
    respond(400, { error => 'bad_request' }) if $@;

}

sub constant_equal {
    my ($a, $b) = @_;
    return 0 unless length($a) == length($b);
    my $diff = 0;
    $diff |= ord(substr($a, $_, 1)) ^ ord(substr($b, $_, 1)) for 0 .. length($a) - 1;
    return $diff == 0;
}
sub respond {
    my ($status, $data) = @_;
    print "Status: $status\r\nContent-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n\r\n", encode_json($data);
}

sub settings_html {
    my ($config) = @_;
    my $settings = ($config->{extensions} || {})->{memory} || {};
    my $checked = $settings->{enabled} ? ' checked' : '';
    my $generic = ($settings->{profile} || '') eq 'sati' ? '' : ' selected';
    my $sati = ($settings->{profile} || '') eq 'sati' ? ' selected' : '';
    return qq|<fieldset><legend>Memory extension</legend>
<input type="hidden" name="extension_memory_present" value="1">
<label><input type="checkbox" name="extension_memory_enabled" value="1"$checked> Enable authenticated memory API</label>
<label>Connection profile <select name="extension_memory_profile"><option value="generic"$generic>Generic</option><option value="sati"$sati>SATi</option></select></label>
<p>Disabled by default. Set separate read/write tokens on the server after enabling. Disabling keeps articles and their privacy protection.</p></fieldset>|;
}
sub save_settings {
    my ($config, $params) = @_;
    return unless ($params->{extension_memory_present} || '') eq '1';
    $config->{extensions}{memory} ||= {};
    $config->{extensions}{memory}{enabled} = ($params->{extension_memory_enabled} || '') eq '1' ? JSON::PP::true : JSON::PP::false;
    $config->{extensions}{memory}{profile} = ($params->{extension_memory_profile} || '') eq 'sati' ? 'sati' : 'generic';
}
return { run => \&run, settings_html => \&settings_html, save_settings => \&save_settings };
