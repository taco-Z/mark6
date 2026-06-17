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
my $root = File::Spec->catdir('t', 'tmp_admin_articles');

remove_tree($root) if -d $root;
make_path(File::Spec->catdir($root, 'dat', 'articles'));
make_path(File::Spec->catdir($root, 'dat', 'sessions'));
write_json(File::Spec->catfile($root, 'dat', 'users.json'), { version => 1, users => [] });
write_json(File::Spec->catfile($root, 'dat', 'config.json'), {
    version => 1,
    site => { title => 'MARK6 Test', language => 'ja', base_url => '' },
});
write_json(File::Spec->catfile($root, 'dat', 'home.json'), {
    title => 'Home',
    body => '',
    show_articles => JSON::PP::true,
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

my $new_form = run_cgi(
    script => File::Spec->catfile('admin', 'articles.cgi'),
    method => 'GET',
    query  => 'command=new',
    cookie => "mark6_session=$session_id",
);
like($new_form, qr/New Article/, 'new article form renders');
my ($csrf) = $new_form =~ /name="csrf_token" value="([0-9a-f]+)"/;
ok($csrf, 'form includes csrf token');

my $save = run_cgi(
    script => File::Spec->catfile('admin', 'articles.cgi'),
    method => 'POST',
    cookie => "mark6_session=$session_id",
    body   => form_data(
        command    => 'save',
        id         => 'test-article',
        csrf_token => $csrf,
        title      => 'テスト記事',
        status     => 'published',
        tags       => 'News, Perl',
        image      => '',
        intro      => '<p>紹介文</p>',
        body       => '<p>本文</p>',
    ),
);
like($save, qr/Location: articles\.cgi/, 'save redirects to article list');

my $list = run_cgi(
    script => File::Spec->catfile('admin', 'articles.cgi'),
    method => 'GET',
    cookie => "mark6_session=$session_id",
);
like($list, qr/テスト記事/, 'saved article appears in admin list');

my $public = run_cgi(
    script => File::Spec->catfile('public', 'index.cgi'),
    method => 'GET',
    query  => 'order=focus&tar=test-article',
);
like($public, qr/テスト記事/, 'saved article appears publicly');
like($public, qr/本文/, 'public detail renders body');

my $delete = run_cgi(
    script => File::Spec->catfile('admin', 'articles.cgi'),
    method => 'POST',
    cookie => "mark6_session=$session_id",
    body   => form_data(
        command    => 'delete',
        id         => 'test-article',
        csrf_token => $csrf,
    ),
);
like($delete, qr/Location: articles\.cgi/, 'delete redirects to article list');

my $after_delete = run_cgi(
    script => File::Spec->catfile('public', 'index.cgi'),
    method => 'GET',
    query  => 'order=focus&tar=test-article',
);
like($after_delete, qr/Article not found/, 'deleted article is hidden publicly');

remove_tree($root);
done_testing;

sub run_cgi {
    my (%args) = @_;
    local $ENV{MARK6_ROOT} = $root;
    local $ENV{REQUEST_METHOD} = $args{method} || 'GET';
    local $ENV{QUERY_STRING} = $args{query} || '';
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

