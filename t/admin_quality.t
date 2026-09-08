use strict;
use warnings;
use Test::More;
use File::Path qw(make_path remove_tree);
use File::Spec;
use JSON::PP ();
use Encode qw(decode encode);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);

my $perl = $^X;
my $root = File::Spec->catdir('t', 'tmp_admin_quality');

remove_tree($root) if -d $root;
make_path(
    File::Spec->catdir($root, 'dat', 'sessions'),
    File::Spec->catdir($root, 'dat', 'articles'),
);
write_json(File::Spec->catfile($root, 'dat', 'users.json'), { version => 1, users => [] });
write_json(File::Spec->catfile($root, 'dat', 'config.json'), {
    version => 1,
    site => { title => 'OITA360 Test', language => 'en', base_url => '', node => 'oita360' },
    content_checker => {
        profile => 'regional_media',
        text_limits => { default => { description_min_chars => 60, body_min_chars => 300 } },
        generic_phrases => ['2018-01-27'],
        profiles => {
            regional_media => {
                location_required_for_types => ['spot'],
            },
        },
    },
});
write_json(File::Spec->catfile($root, 'dat', 'home.json'), {
    title => 'Home',
    body => '',
    show_articles => JSON::PP::true,
});
write_json(File::Spec->catfile($root, 'dat', 'articles', 'bad.json'), {
    id => 'bad',
    node => 'oita360',
    status => 'published',
    title => '2018-01-27',
    slug => 'video-12345678901',
    image => 'https://img.youtube.com/vi/12345678901/hqdefault.jpg',
    tags => ['OITA360'],
    langs => {
        ja => {
            title => '2018-01-27',
            description => 'Short OITA360 description.',
            body => '<iframe></iframe><p>Short body.</p>',
        },
    },
    youtube => { video_id => '12345678901' },
    source => { original_iframe => '<iframe></iframe>' },
    article => {
        series => 'unknown',
        type => 'spot',
        location => { prefecture => 'Oita', city => '', name => '' },
    },
});

my $create = `$perl tools/create_user.pl --root "$root" --name admin --password secret --rank master`;
is($? >> 8, 0, 'create_user exits ok');

my $login = run_cgi(
    script => File::Spec->catfile('admin', 'login.cgi'),
    method => 'POST',
    body   => form_data(name => 'admin', password => 'secret'),
);
my ($session_id) = $login =~ /mark6_session=([0-9a-f]{64})/;
ok($session_id, 'login sets session');

my $dashboard = run_cgi(
    script => File::Spec->catfile('admin', 'index.cgi'),
    cookie => "mark6_session=$session_id",
);
like($dashboard, qr/quality\.cgi/, 'dashboard links to content check page');
like($dashboard, qr/Content Check/, 'dashboard labels the content check link');

my $page = run_cgi(
    script => File::Spec->catfile('admin', 'quality.cgi'),
    cookie => "mark6_session=$session_id",
);
like($page, qr/Content Check/, 'content check page renders');
like($page, qr/Check Articles/, 'content check page has generate action');
like($page, qr/Target is selected automatically/, 'content check page explains automatic target selection');
unlike($page, qr/<select name="profile">/, 'content check page hides profile selection');
unlike($page, qr/name="node" type="text"/, 'content check page hides node text input');
like($page, qr/name="profile" value="regional_media"/, 'content check page uses configured profile');
like($page, qr/name="node" value="oita360"/, 'content check page auto-selects OITA360 node');

my $generate = run_cgi(
    script => File::Spec->catfile('admin', 'quality.cgi'),
    method => 'POST',
    body   => form_data(command => 'generate'),
    cookie => "mark6_session=$session_id",
);
like($generate, qr/Location: quality\.cgi\?profile=regional_media&node=oita360&generated=1/, 'generate redirects back to configured report page');
ok(-e File::Spec->catfile($root, 'logs', 'regional_media_quality_report.md'), 'generates markdown report');
ok(-e File::Spec->catfile($root, 'logs', 'regional_media_quality_report.csv'), 'generates CSV report');

my $csv = run_cgi(
    script => File::Spec->catfile('admin', 'quality.cgi'),
    query  => 'profile=regional_media&node=oita360&format=csv',
    cookie => "mark6_session=$session_id",
);
like($csv, qr/Content-Type: text\/csv/, 'CSV response has content type');
like($csv, qr/Title looks generic/, 'CSV response includes configured generic title finding');
like($csv, qr/city is missing/, 'CSV response includes site profile findings');

remove_tree($root);
done_testing;

sub run_cgi {
    my (%args) = @_;
    local $ENV{MARK6_ROOT} = $root;
    local $ENV{REQUEST_METHOD} = $args{method} || 'GET';
    local $ENV{QUERY_STRING} = $args{query} || '';
    local $ENV{HTTP_COOKIE} = $args{cookie} || '';
    local $ENV{HTTPS} = '';
    local $ENV{CONTENT_TYPE} = 'application/x-www-form-urlencoded';

    my $body = $args{body} || '';
    local $ENV{CONTENT_LENGTH} = length($body);

    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, $perl, $args{script});
    print {$in} $body if $body ne '';
    close $in;
    my $output = do { local $/; <$out> };
    my $error = do { local $/; <$err> };
    waitpid($pid, 0);
    die $error if ($? >> 8) != 0;

    return decode('UTF-8', $output || '');
}

sub form_data {
    my (%pairs) = @_;
    return join '&', map { url_encode($_) . '=' . url_encode($pairs{$_}) } sort keys %pairs;
}

sub url_encode {
    my ($value) = @_;
    $value = encode('UTF-8', $value || '');
    $value =~ s/([^A-Za-z0-9_.~-])/sprintf('%%%02X', ord($1))/eg;
    return $value;
}

sub write_json {
    my ($path, $data) = @_;
    open my $fh, '>:raw', $path or die "Cannot write $path: $!";
    print {$fh} JSON::PP->new->utf8->canonical->pretty->encode($data);
    close $fh;
}
