use strict;
use warnings;
use utf8;
use Test::More;
use File::Path qw(make_path remove_tree);
use File::Spec;
use JSON::PP ();

my $perl = $^X;
my $root = File::Spec->catdir('t', 'tmp_youtube_csv_import');
my $csv = File::Spec->catfile($root, 'table.csv');
my $output = File::Spec->catdir($root, 'articles');

remove_tree($root) if -d $root;
make_path($root);

open my $fh, '>:encoding(UTF-8)', $csv or die "Cannot write $csv: $!";
print {$fh} "コンテンツ,動画のタイトル,動画公開時刻,長さ\n";
print {$fh} "Jce1N0hRfJc,\"Test, Video\",\"Nov 16, 2017\",140\n";
print {$fh} "4oNRjqXyjz0,Second Video,\"Jan 4, 2018\",151\n";
close $fh;

my $command = qq|$perl tools/import_youtube_csv.pl --csv "$csv" --output "$output" --node oita360 --skip-video-id Jce1N0hRfJc|;
my $result = `$command`;
is($? >> 8, 0, 'import command exits successfully');
like($result, qr/Created 1 draft article JSON file/, 'reports one created draft');

my @files = glob File::Spec->catfile($output, '*.json');
is(scalar @files, 1, 'writes one article JSON file');
my $article = read_json($files[0]);
is($article->{status}, 'draft', 'creates a draft article');
is($article->{node}, 'oita360', 'uses supplied node');
is($article->{slug}, 'video-4oNRjqXyjz0', 'uses deterministic video slug');
is($article->{image}, 'https://img.youtube.com/vi/4oNRjqXyjz0/hqdefault.jpg', 'uses YouTube thumbnail');
like($article->{langs}{ja}{body}, qr{youtube\.com/embed/4oNRjqXyjz0}, 'embeds the YouTube video');
is($article->{youtube}{published_at}, '2018-01-04T00:00:00Z', 'converts the publish date');

remove_tree($root);
done_testing;

sub read_json {
    my ($path) = @_;
    open my $fh, '<:raw', $path or die "Cannot read $path: $!";
    local $/;
    return JSON::PP->new->utf8->decode(<$fh>);
}
