use strict;
use warnings;
use Test::More;
use File::Path qw(make_path remove_tree);
use File::Spec;
use JSON::PP ();
use Encode qw(decode);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);

my $perl = $^X;
my $root = File::Spec->catdir('t', 'tmp_admin_auth');

remove_tree($root) if -d $root;
make_path(File::Spec->catdir($root, 'dat', 'sessions'));
write_json(File::Spec->catfile($root, 'dat', 'users.json'), { version => 1, users => [] });

my $create = `$perl tools/create_user.pl --root "$root" --name admin --password secret --rank master`;
is($? >> 8, 0, 'create_user exits ok');
like($create, qr/Created user: admin \(master\)/, 'create_user prints user');

my $login = run_cgi(
    script => File::Spec->catfile('admin', 'login.cgi'),
    method => 'POST',
    body   => 'name=admin&password=secret',
);

like($login, qr/Status: 302 Found/, 'login redirects');
like($login, qr/Location: index\.cgi/, 'login redirects to admin index');
my ($session_id) = $login =~ /mark6_session=([0-9a-f]{64})/;
ok($session_id, 'login sets opaque session cookie');
unlike($login, qr/secret|password=secret/, 'login response does not leak password');

my $dashboard = run_cgi(
    script => File::Spec->catfile('admin', 'index.cgi'),
    method => 'GET',
    cookie => "mark6_session=$session_id",
);

like($dashboard, qr/Dashboard/, 'dashboard renders');
like($dashboard, qr/Logged in as <strong>admin<\/strong> \(master\)/, 'dashboard identifies user');

my $logout = run_cgi(
    script => File::Spec->catfile('admin', 'logout.cgi'),
    method => 'GET',
    cookie => "mark6_session=$session_id",
);

like($logout, qr/Max-Age=0/, 'logout clears cookie');
like($logout, qr/Location: login\.cgi/, 'logout redirects to login');

my $after_logout = run_cgi(
    script => File::Spec->catfile('admin', 'index.cgi'),
    method => 'GET',
    cookie => "mark6_session=$session_id",
);

like($after_logout, qr/Location: login\.cgi/, 'destroyed session cannot access dashboard');

remove_tree($root);
done_testing;

sub run_cgi {
    my (%args) = @_;
    local $ENV{MARK6_ROOT} = $root;
    local $ENV{REQUEST_METHOD} = $args{method} || 'GET';
    local $ENV{QUERY_STRING} = '';
    local $ENV{HTTP_COOKIE} = $args{cookie} || '';
    local $ENV{HTTPS} = '';

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

sub write_json {
    my ($path, $data) = @_;
    open my $fh, '>:raw', $path or die "Cannot write $path: $!";
    print {$fh} JSON::PP->new->utf8->canonical->pretty->encode($data);
    close $fh;
}
