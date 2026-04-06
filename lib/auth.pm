package auth;
use strict;
use warnings;
use utf8;

use Digest::SHA qw(sha256_hex);
use db;
use web;

sub password_hash {
    my ($plain) = @_;
    return sha256_hex(defined $plain ? $plain : '');
}

sub get_cookie_name {
    my ($ctx) = @_;
    return $ctx->{config}->{cookie_name} || 'mark6_sid';
}

sub load_users {
    my ($ctx) = @_;
    return db::load_jsonl($ctx->{path}->{user_db}) || [];
}

sub load_sessions {
    my ($ctx) = @_;
    return db::load_jsonl($ctx->{path}->{session_db}) || [];
}

sub save_sessions {
    my ($ctx, $rows) = @_;
    return db::save_jsonl($ctx->{path}->{session_db}, $rows || []);
}

sub find_user {
    my ($ctx, $id) = @_;
    my $users = load_users($ctx);

    for my $user (@$users) {
        next unless defined $user->{id};
        next unless $user->{id} eq $id;
        next if defined($user->{status}) && !$user->{status};
        return $user;
    }
    return;
}

sub verify_login {
    my ($ctx, $id, $password) = @_;
    my $user = find_user($ctx, $id) or return;
    return (($user->{password_hash} || '') eq password_hash($password)) ? $user : undef;
}

sub create_session_id {
    my ($ctx, $user_id) = @_;
    return sha256_hex(join(':', time, $$, rand(), $user_id || ''));
}

sub cleanup_sessions {
    my ($ctx) = @_;
    my $rows = load_sessions($ctx);
    my $now  = time;
    my @alive = grep { ($_->{expire} || 0) > $now } @$rows;
    save_sessions($ctx, \@alive);
    return \@alive;
}

sub create_session {
    my ($ctx, $user_id) = @_;
    my $rows = cleanup_sessions($ctx);
    my $sid  = create_session_id($ctx, $user_id);
    my $exp  = time + (($ctx->{config}->{session_hours} || 12) * 3600);

    push @$rows, {
        session => $sid,
        user    => $user_id,
        expire  => int($exp),
    };

    save_sessions($ctx, $rows);
    return $sid;
}

sub current_session_id {
    my ($ctx) = @_;
    my $name = get_cookie_name($ctx);
    return $ctx->{cookies}->{$name};
}

sub get_login_user {
    my ($ctx) = @_;
    my $sid = current_session_id($ctx) or return;
    my $rows = cleanup_sessions($ctx);
    my $now  = time;

    for my $row (@$rows) {
        next unless ($row->{session} || '') eq $sid;
        next unless ($row->{expire} || 0) > $now;
        return find_user($ctx, $row->{user});
    }

    return;
}

sub current_user { return get_login_user(@_); }

sub login {
    my ($ctx, $id, $password) = @_;
    my $user = verify_login($ctx, $id, $password) or return { ok => 0 };
    my $sid = create_session($ctx, $user->{id});

    return {
        ok     => 1,
        user   => $user,
        cookie => login_cookie($ctx, $sid),
    };
}

sub require_login { return get_login_user(@_); }

sub login_cookie {
    my ($ctx, $sid) = @_;
    return web::make_cookie(
        name     => get_cookie_name($ctx),
        value    => $sid,
        path     => '/',
        httponly => 1,
    );
}

sub logout_cookie {
    my ($ctx) = @_;
    return web::make_cookie(
        name     => get_cookie_name($ctx),
        value    => '',
        path     => '/',
        expires  => 'Thu, 01 Jan 1970 00:00:00 GMT',
        httponly => 1,
    );
}

sub logout_session {
    my ($ctx) = @_;
    my $sid = current_session_id($ctx);
    my $rows = load_sessions($ctx);
    my @keep = grep { ($_->{session} || '') ne ($sid || '') } @$rows;
    save_sessions($ctx, \@keep);
    return 1;
}

sub logout {
    my ($ctx) = @_;
    logout_session($ctx);
    return logout_cookie($ctx);
}

1;