use strict;
use warnings;
use Test::More;
use File::Path qw(make_path remove_tree);
use File::Spec;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Mark6::Auth;

my $root = File::Spec->catdir($FindBin::Bin, 'tmp_auth');
remove_tree($root) if -d $root;
make_path(File::Spec->catdir($root, 'dat', 'sessions'));

my $auth = Mark6::Auth->new(root => $root);

my $hash = $auth->hash_password('secret', iterations => 2, salt_hex => '000102030405060708090a0b0c0d0e0f');
like($hash, qr/^pbkdf2_sha256\$/, 'password hash has scheme');
ok($auth->verify_password('secret', $hash), 'password verifies');
ok(!$auth->verify_password('wrong', $hash), 'wrong password fails');

my $session = $auth->create_session(
    user_id    => 'u1',
    ip         => '127.0.0.1',
    user_agent => 'test',
    ttl        => 60,
);

ok($session->{session_id}, 'session id returned');
ok($session->{csrf_token}, 'csrf token returned');

my $stored = $auth->read_session($session->{session_id});
is($stored->{user_id}, 'u1', 'session persisted');
ok($auth->verify_csrf($stored, $session->{csrf_token}), 'csrf verifies');
ok(!$auth->verify_csrf($stored, 'bad'), 'bad csrf fails');

$auth->destroy_session($session->{session_id});
ok(!$auth->read_session($session->{session_id}), 'session destroyed');

remove_tree($root);
done_testing;

