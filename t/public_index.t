use strict;
use warnings;
use Test::More;
use File::Path qw(make_path remove_tree);
use File::Spec;
use JSON::PP ();
use Encode qw(decode);

my $perl = $^X;
my $script = File::Spec->catfile('public', 'index.cgi');
my $root = File::Spec->catdir('t', 'tmp_public_index');

remove_tree($root) if -d $root;
make_path(File::Spec->catdir($root, 'dat', 'articles'));

write_json(File::Spec->catfile($root, 'dat', 'config.json'), {
    version => 1,
    site => {
        title => 'MARK6 Test',
        language => 'ja',
        default_lang => 'ja',
        langs => ['ja', 'en'],
        node => 'oita360',
        base_url => '',
    },
    features => {
        tags => JSON::PP::true,
        newest => JSON::PP::true,
        popular => JSON::PP::true,
        shop => JSON::PP::false,
        ai => JSON::PP::false,
    },
});

write_json(File::Spec->catfile($root, 'dat', 'home.json'), {
    title => 'ようこそ',
    body => '<p>Home body</p>',
    show_articles => JSON::PP::true,
    updated_at => '',
});

write_json(File::Spec->catfile($root, 'dat', 'articles', '1375451805.json'), {
    id => '1375451805',
    type => 'article',
    status => 'published',
    default_lang => 'ja',
    node => 'oita360',
    slug => 'beppu-station',
    langs => {
        ja => {
            title => '別府駅',
            description => '<p>別府駅の紹介</p>',
            body => '<p>日本語本文です。</p>',
        },
        en => {
            title => 'Beppu Station',
            description => '<p>About Beppu Station</p>',
            body => '',
        },
    },
    tags => ['News'],
    image => '',
    created_at => '2013-08-02T13:56:45Z',
});

my $home = run_cgi('');
like($home, qr/Content-Type: text\/html; charset=UTF-8/, 'prints UTF-8 content type');
like($home, qr/ようこそ/, 'renders home title');
like($home, qr/別府駅/, 'renders default language article summary');
like($home, qr/href="\/ja\/oita360\/beppu-station\/"/, 'renders localized article URL');
like($home, qr/class="language-switch"/, 'renders language switch links');

my $detail = run_cgi('order=focus&tar=1375451805');
like($detail, qr/別府駅/, 'renders legacy detail title');
like($detail, qr/日本語本文です。/, 'renders legacy detail body');
like($detail, qr/href="\/en\/oita360\/beppu-station\/"/, 'detail links alternate language');

my $en_detail = run_cgi('', '/en/oita360/beppu-station/');
like($en_detail, qr/Beppu Station/, 'renders English detail title from path URL');
like($en_detail, qr/日本語本文です。/, 'falls back to default body when untranslated');

my $list = run_cgi('order=article&tag=News');
like($list, qr/Tag: News/, 'renders tag page');
like($list, qr/別府駅/, 'renders filtered article');

remove_tree($root);
done_testing;

sub run_cgi {
    my ($query, $path_info) = @_;
    local $ENV{QUERY_STRING} = $query;
    local $ENV{PATH_INFO} = $path_info || '';
    local $ENV{REQUEST_METHOD} = 'GET';
    local $ENV{MARK6_ROOT} = $root;

    my $output = `$perl $script`;
    my $exit = $? >> 8;
    die "CGI failed with exit $exit" if $exit;
    return decode('UTF-8', $output);
}

sub write_json {
    my ($path, $data) = @_;
    open my $fh, '>:raw', $path or die "Cannot write $path: $!";
    print {$fh} JSON::PP->new->utf8->canonical->pretty->encode($data);
    close $fh;
}
