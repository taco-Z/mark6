use strict;
use warnings;
use Test::More;
use File::Path qw(make_path remove_tree);
use File::Spec;
use JSON::PP ();
use lib 'lib';
use Mark6::QualityReport;

my $root = File::Spec->catdir('t', 'tmp_content_checker_v2');
my $articles = File::Spec->catdir($root, 'dat', 'articles');
remove_tree($root) if -d $root;
make_path($articles);
write_json(File::Spec->catfile($root, 'dat', 'config.json'), {
    site => { language => 'ja', langs => ['ja', 'en'] },
    content_checker => {
        text_limits => { default => { description_min_chars => 10, body_min_chars => 10 } },
        profiles => { regional_media => { location_required_for_types => ['spot'] } },
    },
});

my $checker = Mark6::QualityReport->new(root => $root, profile => 'default');
my $info_only = {
    id => 'info', status => 'published', slug => 'good-content', default_lang => 'ja',
    langs => {
        ja => { title => 'A real title', description => 'Specific place description', body => 'Long enough body' },
        en => { title => 'A real title', description => 'Specific place description', body => 'Long enough body' },
    },
};
my $row = $checker->analyze_article($info_only, 'info.json');
is($row->{status}, 'OK', 'missing original description is INFO only');
is($row->{score}, 0, 'INFO does not add risk score');
is($row->{info_count}, 1, 'provenance INFO is counted separately');

my $diy = { %{$info_only}, id => 'diy', article => { type => 'diy', location => {} }, content_profile => 'regional_media' };
$row = $checker->analyze_article($diy, 'diy.json');
unlike(join(';', @{$row->{issues}}), qr/location\.city/, 'location is not required for a non-location type');

my $spot = { %{$info_only}, id => 'spot', article => { type => 'spot', location => {} }, content_profile => 'regional_media' };
$row = $checker->analyze_article($spot, 'spot.json');
like(join(';', @{$row->{issues}}), qr/location\.city/, 'location profile adds a city recommendation');
is($row->{status}, 'OK', 'recommended metadata does not block publication');

my $missing_body = { %{$info_only}, id => 'missing-body', langs => { ja => { title => 'Title', description => 'A useful description', body => '' } } };
$row = $checker->analyze_article($missing_body, 'missing-body.json');
is($row->{priority}, 'P0', 'published content without body is critical');
is($row->{status}, 'BLOCK', 'P0 produces BLOCK status');

my $draft = { %{$info_only}, id => 'draft', status => 'draft', langs => { ja => { title => 'Draft', description => '', body => '' } } };
$row = $checker->analyze_article($draft, 'draft.json');
is($row->{status}, 'OK', 'draft content is not blocked by missing body or description');
ok($row->{p3_count} >= 2, 'draft omissions are downgraded to P3');

my $en_required = { %{$info_only}, id => 'en-required', content_profile => 'default', langs => { ja => $info_only->{langs}{ja} } };
$row = $checker->analyze_article($en_required, 'en-required.json');
is($row->{priority}, 'P1', 'enabled language with missing body is P1');
like(join(';', @{$row->{issues}}), qr/Translation body is missing for en/, 'language issue names the missing language');

remove_tree($root);
done_testing;

sub write_json {
    my ($path, $data) = @_;
    open my $fh, '>:encoding(UTF-8)', $path or die "Cannot write $path: $!";
    print {$fh} JSON::PP->new->utf8(0)->canonical->encode($data);
    close $fh;
}
