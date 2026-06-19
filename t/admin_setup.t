use strict;
use warnings;
use utf8;
use Test::More;
use File::Path qw(make_path remove_tree);
use File::Spec;
use JSON::PP ();
use Encode qw(decode encode);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);

my $perl = $^X;
my $root = File::Spec->catdir('t', 'tmp_admin_setup');

remove_tree($root) if -d $root;
make_path(File::Spec->catdir($root, 'dat'));
write_json(File::Spec->catfile($root, 'dat', 'users.json'), { version => 1, users => [] });

my $login_before_setup = run_cgi(
    script => File::Spec->catfile('admin', 'login.cgi'),
    method => 'GET',
);
like($login_before_setup, qr/Location: setup\.cgi/, 'login redirects to setup when no users exist');

my $index_before_setup = run_cgi(
    script => File::Spec->catfile('admin', 'index.cgi'),
    method => 'GET',
);
like($index_before_setup, qr/Location: setup\.cgi/, 'admin index redirects to setup when no users exist');

open my $empty_users, '>:raw', File::Spec->catfile($root, 'dat', 'users.json') or die "Cannot empty users.json: $!";
close $empty_users;
my $empty_users_index = run_cgi(
    script => File::Spec->catfile('admin', 'index.cgi'),
    method => 'GET',
);
like($empty_users_index, qr/Location: setup\.cgi/, 'admin index redirects to setup when users file is empty');
write_json(File::Spec->catfile($root, 'dat', 'users.json'), { version => 1, users => [] });

my $setup_form = run_cgi(
    script => File::Spec->catfile('admin', 'setup.cgi'),
    method => 'GET',
);
like($setup_form, qr/MARK6 初期設定/, 'setup form renders');

my $setup = run_cgi(
    script => File::Spec->catfile('admin', 'setup.cgi'),
    method => 'POST',
    body => form_data(
        site_title => '初期サイト',
        language => 'ja',
        name => 'admin',
        password => 'secret123',
        password_confirm => 'secret123',
    ),
);
like($setup, qr/Location: index\.cgi/, 'setup redirects to admin index');
my ($session_id) = $setup =~ /mark6_session=([0-9a-f]{64})/;
ok($session_id, 'setup creates login session');

ok(-e File::Spec->catfile($root, 'dat', 'config.json'), 'config written');
ok(-e File::Spec->catfile($root, 'dat', 'home.json'), 'home written');
ok(-d File::Spec->catdir($root, 'dat', 'articles'), 'articles directory created');
ok(-d File::Spec->catdir($root, 'dat', 'media'), 'media directory created');
ok(-d File::Spec->catdir($root, 'img', 'uploads'), 'uploads directory created');

my $config = read_json(File::Spec->catfile($root, 'dat', 'config.json'));
is($config->{site}{title}, '初期サイト', 'site title saved');
is($config->{site}{language}, 'ja', 'language saved');
is($config->{ai}{provider}, 'openai', 'setup writes AI provider');
is($config->{ai}{model}, 'gpt-5.2', 'setup writes default AI model');
is($config->{ai}{api_key_env}, 'MARK6_OPENAI_API_KEY', 'setup writes AI key environment name');

my $home = read_json(File::Spec->catfile($root, 'dat', 'home.json'));
is($home->{title}, 'ホーム', 'Japanese setup creates Japanese home title');

my $users = read_json(File::Spec->catfile($root, 'dat', 'users.json'));
is(scalar @{$users->{users}}, 1, 'one admin user created');
is($users->{users}[0]{name}, 'admin', 'admin user name saved');
is($users->{users}[0]{rank}, 'master', 'admin user rank is master');
ok($users->{users}[0]{password_hash}, 'admin password hash saved');
unlike($users->{users}[0]{password_hash}, qr/secret123/, 'plain password not saved');

my $setup_again = run_cgi(
    script => File::Spec->catfile('admin', 'setup.cgi'),
    method => 'GET',
);
like($setup_again, qr/Location: login\.cgi/, 'setup redirects to login after initialization');

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

sub read_json {
    my ($path) = @_;
    open my $fh, '<:raw', $path or die "Cannot read $path: $!";
    local $/;
    my $body = <$fh>;
    close $fh;
    return JSON::PP->new->utf8->decode($body);
}
