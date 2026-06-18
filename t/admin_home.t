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
my $root = File::Spec->catdir('t', 'tmp_admin_home');

remove_tree($root) if -d $root;
make_path(File::Spec->catdir($root, 'dat', 'sessions'));
write_json(File::Spec->catfile($root, 'dat', 'users.json'), { version => 1, users => [] });
write_json(File::Spec->catfile($root, 'dat', 'config.json'), {
    version => 1,
    site => { title => 'MARK6 Test', language => 'ja', base_url => '' },
    features => { tags => JSON::PP::true, newest => JSON::PP::true, popular => JSON::PP::true, shop => JSON::PP::false, ai => JSON::PP::false },
    display => { articles_per_page => 20, mini_articles => 15 },
    shop => { title => 'Shop', paypal_id => '' },
});
write_json(File::Spec->catfile($root, 'dat', 'home.json'), {
    title => 'Before Home',
    body => '<p>Before body</p>',
    show_articles => JSON::PP::true,
    updated_at => '',
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
    method => 'GET',
    cookie => "mark6_session=$session_id",
);
like($dashboard, qr/home\.cgi/, 'dashboard links to home editor');

my $home_form = run_cgi(
    script => File::Spec->catfile('admin', 'home.cgi'),
    method => 'GET',
    cookie => "mark6_session=$session_id",
);
like($home_form, qr/Before Home/, 'home editor renders current title');
like($home_form, qr/Before body/, 'home editor renders current body');
my ($csrf) = $home_form =~ /name="csrf_token" value="([0-9a-f]+)"/;
ok($csrf, 'home editor includes csrf token');

my $save = run_cgi(
    script => File::Spec->catfile('admin', 'home.cgi'),
    method => 'POST',
    cookie => "mark6_session=$session_id",
    body => form_data(
        csrf_token => $csrf,
        title => 'After Home',
        body => '<p>After body</p>',
    ),
);
like($save, qr/Location: home\.cgi\?saved=1/, 'home save redirects');

my $home = read_json(File::Spec->catfile($root, 'dat', 'home.json'));
is($home->{title}, 'After Home', 'home title saved');
is($home->{body}, '<p>After body</p>', 'home body saved');
ok(!$home->{show_articles}, 'unchecked show_articles saved false');
ok($home->{updated_at}, 'updated_at saved');

my $public = run_cgi(
    script => File::Spec->catfile('public', 'index.cgi'),
    method => 'GET',
    path_info => '/ja/',
);
like($public, qr/After Home/, 'public page shows updated home title');
like($public, qr/After body/, 'public page shows updated home body');

remove_tree($root);
done_testing;

sub run_cgi {
    my (%args) = @_;
    local $ENV{MARK6_ROOT} = $root;
    local $ENV{REQUEST_METHOD} = $args{method} || 'GET';
    local $ENV{QUERY_STRING} = $args{query} || '';
    local $ENV{PATH_INFO} = $args{path_info} || '';
    local $ENV{HTTP_COOKIE} = $args{cookie} || '';
    local $ENV{HTTPS} = '';
    local $ENV{CONTENT_TYPE} = $args{content_type} || 'application/x-www-form-urlencoded';

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

sub read_json {
    my ($path) = @_;
    open my $fh, '<:raw', $path or die "Cannot read $path: $!";
    local $/;
    my $body = <$fh>;
    close $fh;
    return JSON::PP->new->utf8->decode($body);
}
