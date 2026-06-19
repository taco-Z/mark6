use strict;
use warnings;
use utf8;
use Test::More;
use File::Path qw(make_path remove_tree);
use File::Spec;
use JSON::PP ();
use Encode qw(decode);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);

my $perl = $^X;
my $root = File::Spec->catdir('t', 'tmp_admin_layout');

remove_tree($root) if -d $root;
make_path(File::Spec->catdir($root, 'dat', 'sessions'));
make_path(File::Spec->catdir($root, 'dat', 'articles'));
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
    body   => 'name=admin&password=secret',
);
my ($session_id) = $login =~ /mark6_session=([0-9a-f]{64})/;
ok($session_id, 'login sets session');

for my $case (
    ['admin/index.cgi',    'dashboard', 'Dashboard'],
    ['admin/home.cgi',     'home',      'Home'],
    ['admin/articles.cgi', 'articles',  'Articles'],
    ['admin/media.cgi',    'media',     'Media'],
    ['admin/settings.cgi', 'settings',  'Settings'],
) {
    my ($script, $active, $title) = @{$case};
    my $active_href = $active eq 'dashboard' ? 'index.cgi' : "$active.cgi";
    my $page = run_cgi(
        script => File::Spec->catfile(split('/', $script)),
        method => 'GET',
        cookie => "mark6_session=$session_id",
    );

    like($page, qr/<html lang="ja">/, "$title page sets Japanese html language");
    like($page, qr/MARK6 管理画面/, "$title page uses admin layout");
    like($page, qr/class="site-nav admin-nav"/, "$title page uses shared admin nav");
    like($page, qr/<a class="active" href="\Q$active_href\E">/, "$title page marks active nav");
    like($page, qr/サイト表示/, "$title nav uses Japanese labels");
    like($page, qr/home\.cgi/, "$title nav links home");
    like($page, qr/articles\.cgi/, "$title nav links articles");
    like($page, qr/media\.cgi/, "$title nav links media");
    like($page, qr/settings\.cgi/, "$title nav links settings");
    like($page, qr/logout\.cgi/, "$title nav links logout");
    like($page, qr/href="\.\.\/public\/index\.cgi" target="_blank" rel="noopener"/, "$title nav opens site view in a new tab");
}

write_json(File::Spec->catfile($root, 'dat', 'config.json'), {
    version => 1,
    site => { title => 'MARK6 Test', language => 'en', base_url => '' },
});

my $english_page = run_cgi(
    script => File::Spec->catfile('admin', 'index.cgi'),
    method => 'GET',
    cookie => "mark6_session=$session_id",
);
like($english_page, qr/<html lang="en">/, 'English admin page sets html language');
like($english_page, qr/MARK6 Admin/, 'English admin page uses English title');
like($english_page, qr/>Dashboard<\/a>/, 'English admin nav uses Dashboard label');
like($english_page, qr/>View Site<\/a>/, 'English admin nav uses View Site label');
unlike($english_page, qr/サイト表示/, 'English admin nav does not keep Japanese labels');

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

sub write_json {
    my ($path, $data) = @_;
    open my $fh, '>:raw', $path or die "Cannot write $path: $!";
    print {$fh} JSON::PP->new->utf8->canonical->pretty->encode($data);
    close $fh;
}
