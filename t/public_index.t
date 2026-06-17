use strict;
use warnings;
use Test::More;
use File::Path qw(make_path remove_tree);
use File::Spec;
use JSON::PP qw(encode_json);
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
    title => 'turbo-works.comへようこそ！',
    body => '<p>Home body</p>',
    show_articles => JSON::PP::true,
    updated_at => '',
});

write_json(File::Spec->catfile($root, 'dat', 'articles', '1375451805.json'), {
    id => '1375451805',
    type => 'article',
    status => 'published',
    title => 'MARK4のアップデートを実施しました',
    tags => ['News'],
    image => '',
    intro => '<p>7月9日</p>',
    body => '<p>本文です。</p>',
    created_at => '2013-08-02T13:56:45Z',
});

my $home = run_cgi('');
like($home, qr/Content-Type: text\/html; charset=UTF-8/, 'prints UTF-8 content type');
like($home, qr/turbo-works\.comへようこそ！/, 'renders migrated home title');
like($home, qr/MARK4のアップデートを実施しました/, 'renders article summary');

my $detail = run_cgi('order=focus&tar=1375451805');
like($detail, qr/MARK4のアップデートを実施しました/, 'renders detail title');
like($detail, qr/本文です。/, 'renders detail body');

my $list = run_cgi('order=article&tag=News');
like($list, qr/Tag: News/, 'renders tag page');
like($list, qr/MARK4のアップデートを実施しました/, 'renders filtered article');

remove_tree($root);
done_testing;

sub run_cgi {
    my ($query) = @_;
    local $ENV{QUERY_STRING} = $query;
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
