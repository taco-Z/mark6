package Mark6::Auth;

use strict;
use warnings;
use Digest::SHA qw(hmac_sha256 hmac_sha256_hex sha256_hex);
use JSON::PP ();
use Mark6::DataStore;

my $DEFAULT_ITERATIONS = 120_000;
my $SESSION_TTL        = 60 * 60 * 8;

sub new {
    my ($class, %args) = @_;
    my $root = $args{root} || '.';

    return bless {
        root  => $root,
        store => Mark6::DataStore->new(root => $root),
    }, $class;
}

sub hash_password {
    my ($self, $password, %args) = @_;
    die "Password is required" unless defined $password && $password ne '';

    my $iterations = $args{iterations} || $DEFAULT_ITERATIONS;
    my $salt = $args{salt_hex} ? _hex_to_bytes($args{salt_hex}) : _random_bytes(16);
    my $hash = _pbkdf2_sha256($password, $salt, $iterations, 32);

    return join('$', 'pbkdf2_sha256', $iterations, _bytes_to_hex($salt), _bytes_to_hex($hash));
}

sub verify_password {
    my ($self, $password, $stored) = @_;
    return 0 unless defined $password && defined $stored;

    my ($scheme, $iterations, $salt_hex, $hash_hex) = split(/\$/, $stored);
    return 0 unless ($scheme || '') eq 'pbkdf2_sha256';
    return 0 unless ($iterations || '') =~ /^\d+$/;
    return 0 unless ($salt_hex || '') =~ /^[0-9a-f]+$/i;
    return 0 unless ($hash_hex || '') =~ /^[0-9a-f]+$/i;

    my $candidate = $self->hash_password(
        $password,
        iterations => 0 + $iterations,
        salt_hex   => lc $salt_hex,
    );

    return _constant_time_eq($candidate, $stored);
}

sub load_users {
    my ($self) = @_;
    return $self->{store}->read_json('dat', 'users.json') || { version => 1, users => [] };
}

sub save_users {
    my ($self, $users) = @_;
    $users->{version} ||= 1;
    $users->{users} ||= [];
    return $self->{store}->write_json($users, 'dat', 'users.json');
}

sub find_user_by_name {
    my ($self, $name) = @_;
    return undef unless defined $name && $name ne '';

    my $users = $self->load_users;
    for my $user (@{$users->{users} || []}) {
        return $user if ($user->{name} || '') eq $name;
    }

    return undef;
}

sub find_user_by_id {
    my ($self, $id) = @_;
    return undef unless defined $id && $id ne '';

    my $users = $self->load_users;
    for my $user (@{$users->{users} || []}) {
        return $user if ($user->{id} || '') eq "$id";
    }

    return undef;
}

sub authenticate {
    my ($self, $name, $password) = @_;
    my $user = $self->find_user_by_name($name);
    return undef unless $user;
    return undef if $user->{password_reset_required};
    return undef unless $self->verify_password($password, $user->{password_hash} || '');
    return $user;
}

sub create_user {
    my ($self, %args) = @_;
    my $name = $args{name} || '';
    my $password = $args{password} || '';
    my $rank = $args{rank} || 'master';

    die "User name is required" if $name eq '';
    die "Password is required" if $password eq '';
    die "Invalid rank" unless $rank =~ /\A(?:master|staff|writer)\z/;

    my $users = $self->load_users;
    for my $user (@{$users->{users} || []}) {
        die "User already exists: $name" if ($user->{name} || '') eq $name;
    }

    my $now = time;
    my $user = {
        id                      => "$now",
        name                    => $name,
        rank                    => $rank,
        password_hash           => $self->hash_password($password),
        legacy_password_hash    => '',
        password_reset_required => JSON::PP::false,
        created_at              => _epoch_to_iso($now),
        updated_at              => _epoch_to_iso($now),
    };

    push @{$users->{users}}, $user;
    $self->save_users($users);

    return $user;
}

sub create_session {
    my ($self, %args) = @_;
    die "user_id is required" unless $args{user_id};

    my $session_id = _bytes_to_hex(_random_bytes(32));
    my $csrf_token = _bytes_to_hex(_random_bytes(32));
    my $now = time;

    my $session = {
        id              => $session_id,
        user_id         => "$args{user_id}",
        created_at      => _epoch_to_iso($now),
        expires_at      => _epoch_to_iso($now + ($args{ttl} || $SESSION_TTL)),
        expires_epoch   => $now + ($args{ttl} || $SESSION_TTL),
        ip_hash         => _fingerprint($args{ip} || ''),
        user_agent_hash => _fingerprint($args{user_agent} || ''),
        csrf_token      => $csrf_token,
        csrf_token_hash => sha256_hex($csrf_token),
    };

    $self->{store}->write_json($session, 'dat', 'sessions', "$session_id.json");

    return {
        session_id => $session_id,
        csrf_token => $csrf_token,
        expires_at => $session->{expires_at},
    };
}

sub read_session {
    my ($self, $session_id) = @_;
    return undef unless defined $session_id && $session_id =~ /^[0-9a-f]{64}$/;

    my $session = $self->{store}->read_json('dat', 'sessions', "$session_id.json");
    return undef unless $session;
    return undef if ($session->{expires_epoch} || 0) < time;

    return $session;
}

sub verify_csrf {
    my ($self, $session, $token) = @_;
    return 0 unless $session && defined $token;
    return _constant_time_eq(sha256_hex($token), $session->{csrf_token_hash} || '');
}

sub destroy_session {
    my ($self, $session_id) = @_;
    return unless defined $session_id && $session_id =~ /^[0-9a-f]{64}$/;

    my $path = $self->{store}->path('dat', 'sessions', "$session_id.json");
    unlink $path if -e $path;
    return 1;
}

sub session_cookie_header {
    my ($self, $session_id, %args) = @_;
    my $secure = exists $args{secure} ? $args{secure} : 1;
    my @flags = (
        "mark6_session=$session_id",
        'Path=/',
        'HttpOnly',
        'SameSite=Strict',
    );
    push @flags, 'Secure' if $secure;
    return 'Set-Cookie: ' . join('; ', @flags);
}

sub clear_session_cookie_header {
    return 'Set-Cookie: mark6_session=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0';
}

sub _pbkdf2_sha256 {
    my ($password, $salt, $iterations, $length) = @_;
    my $blocks = int(($length + 31) / 32);
    my $output = '';

    for my $block (1 .. $blocks) {
        my $u = hmac_sha256($salt . pack('N', $block), $password);
        my $t = $u;

        for (2 .. $iterations) {
            $u = hmac_sha256($u, $password);
            $t ^= $u;
        }

        $output .= $t;
    }

    return substr($output, 0, $length);
}

sub _random_bytes {
    my ($length) = @_;

    if (open my $fh, '<:raw', '/dev/urandom') {
        read($fh, my $bytes, $length) == $length or die "Cannot read random bytes";
        close $fh;
        return $bytes;
    }

    die "Secure random source is not available";
}

sub _fingerprint {
    my ($value) = @_;
    return sha256_hex($value || '');
}

sub _constant_time_eq {
    my ($left, $right) = @_;
    return 0 unless defined $left && defined $right;
    return 0 unless length($left) == length($right);

    my $diff = 0;
    for my $i (0 .. length($left) - 1) {
        $diff |= ord(substr($left, $i, 1)) ^ ord(substr($right, $i, 1));
    }

    return $diff == 0 ? 1 : 0;
}

sub _bytes_to_hex {
    return unpack('H*', $_[0]);
}

sub _hex_to_bytes {
    return pack('H*', $_[0]);
}

sub _epoch_to_iso {
    my ($value) = @_;
    my @t = gmtime($value);
    return sprintf('%04d-%02d-%02dT%02d:%02d:%02dZ',
        $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0]);
}

1;
