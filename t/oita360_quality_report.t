use strict;
use warnings;
use utf8;
use Test::More;
use File::Path qw(make_path remove_tree);
use File::Spec;
use JSON::PP ();

my $perl = $^X;
my $root = File::Spec->catdir('t', 'tmp_oita360_quality_report');
my $articles = File::Spec->catdir($root, 'dat', 'articles');
my $report = File::Spec->catfile($root, 'logs', 'quality.md');
my $csv = File::Spec->catfile($root, 'logs', 'quality.csv');

remove_tree($root) if -d $root;
make_path($articles);
make_path(File::Spec->catdir($root, 'dat'));
write_json(File::Spec->catfile($root, 'dat', 'config.json'), {
    site => { language => 'ja', langs => ['ja'] },
    content_checker => {
        profile => 'regional_media',
        text_limits => { ja => { description_min_chars => 60, body_min_chars => 300 } },
        generic_phrases => ['2018年1月27日'],
        profiles => { regional_media => { location_required_for_types => ['spot'] } },
    },
});

write_json(File::Spec->catfile($articles, 'bad.json'), {
    id           => 'bad',
    node         => 'oita360',
    status       => 'published',
    title        => '2018年1月27日',
    slug         => 'video-12345678901',
    intro        => '周辺の風景を360度動画で確認できるOITA360記事です。見どころと確認ポイントを整理しました。',
    image        => 'https://img.youtube.com/vi/12345678901/hqdefault.jpg',
    tags         => ['OITA360'],
    langs        => {
        ja => {
            title       => '2018年1月27日',
            description => '周辺の風景を360度動画で確認できるOITA360記事です。見どころと確認ポイントを整理しました。',
            body        => '<iframe></iframe><p>短い本文です。</p>',
        },
    },
    youtube      => { video_id => '12345678901' },
    source       => { original_iframe => '<iframe></iframe>' },
    article      => {
        series   => 'オオイタビ',
        type     => 'spot',
        location => { prefecture => '大分県', city => '', name => '' },
    },
});

write_json(File::Spec->catfile($articles, 'ok.json'), {
    id           => 'ok',
    node         => 'oita360',
    status       => 'published',
    title        => 'オオイタビ 由布岳を登る',
    slug         => 'yufudake-climb',
    intro        => '由布岳周辺の登山ルートや景色を360度動画で確認できる記事です。訪問前の下見に使いやすいよう、見どころを整理しています。',
    image        => 'https://img.youtube.com/vi/abcdefghijk/hqdefault.jpg',
    tags         => ['OITA360', '大分県', '由布市', '登山', '360度動画'],
    langs        => {
        ja => {
            title       => 'オオイタビ 由布岳を登る',
            description => '由布岳周辺の登山ルートや景色を360度動画で確認できる記事です。訪問前の下見に使いやすいよう、見どころを整理しています。',
            body        => '<iframe></iframe><p>' . ('本文 ' x 260) . '</p>',
        },
    },
    youtube      => { video_id => 'abcdefghijk' },
    source       => { original_iframe => '<iframe></iframe>', original_description => '由布岳の説明文' },
    ai           => { seo_description => '由布岳周辺の登山ルートや景色を360度動画で確認できる記事です。' },
    article      => {
        series   => 'オオイタビ',
        type     => 'walk',
        location => { prefecture => '大分県', city => '由布市', name => '由布岳' },
    },
});

write_json(File::Spec->catfile($articles, 'about.json'), {
    id           => 'about',
    type         => 'page',
    status       => 'published',
    title        => 'About OITA360',
    slug         => 'about',
    default_lang => 'ja',
    langs        => {
        ja => {
            title       => 'OITA360について',
            description => '固定ページは記事品質レポートの対象外です。',
            body        => '<p>固定ページ本文</p>',
        },
    },
});

my $command = qq|$perl tools/oita360/oita360_quality_report.pl --root "$root" --output "$report" --csv "$csv"|;
my $result = `$command`;
is($? >> 8, 0, 'quality report exits successfully');
like($result, qr/Scanned 2 article/, 'prints scanned count');
ok(-e $report, 'writes markdown report');
ok(-e $csv, 'writes CSV report');

my $markdown = read_text($report);
like($markdown, qr/Title looks generic/, 'flags configured generic title');
like($markdown, qr/city is missing/, 'flags missing city');
unlike($markdown, qr/type is still generic/, 'does not score generic content type');
like($markdown, qr/オオイタビ 由布岳を登る/, 'includes OK article');
unlike($markdown, qr/OITA360について/, 'excludes fixed pages from article quality report');

remove_tree($root);
done_testing;

sub write_json {
    my ($path, $data) = @_;
    open my $fh, '>:encoding(UTF-8)', $path or die "Cannot write $path: $!";
    print {$fh} JSON::PP->new->utf8(0)->pretty->canonical->encode($data);
    close $fh;
}

sub read_text {
    my ($path) = @_;
    open my $fh, '<:encoding(UTF-8)', $path or die "Cannot read $path: $!";
    local $/;
    return <$fh>;
}
