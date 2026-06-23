use strict;
use warnings;
use Test::More;
use File::Path qw(make_path remove_tree);
use File::Spec;
use JSON::PP ();

use Mark6::Stats;

my $root = File::Spec->catdir('t', 'tmp_stats');
remove_tree($root) if -d $root;
make_path(File::Spec->catdir($root, 'dat', 'logs'));

my @now = gmtime(time);
my $today = sprintf('%04d-%02d-%02d', $now[5] + 1900, $now[4] + 1, $now[3]);
my @week = gmtime(time - 3 * 24 * 60 * 60);
my $week_day = sprintf('%04d-%02d-%02d', $week[5] + 1900, $week[4] + 1, $week[3]);
my @old = gmtime(time - 10 * 24 * 60 * 60);
my $old_day = sprintf('%04d-%02d-%02d', $old[5] + 1900, $old[4] + 1, $old[3]);

my $path = File::Spec->catfile($root, 'dat', 'logs', 'access.jsonl');
open my $fh, '>:raw', $path or die "Cannot write $path: $!";
for my $event (
    { kind => 'page', day => $today, article_id => 'a', article_title => 'Article A' },
    { kind => 'page', day => $today, article_id => 'a', article_title => 'Article A' },
    { kind => 'page', day => $week_day, article_id => 'b', article_title => 'Article B' },
    { kind => 'page', day => $old_day, article_id => '', article_title => '' },
) {
    print {$fh} JSON::PP->new->utf8->encode($event), "\n";
}
close $fh;

my $summary = Mark6::Stats->new(root => $root)->access_summary();
is($summary->{today_views}, 2, 'counts today views');
is($summary->{week_views}, 3, 'counts seven day views');
is($summary->{total_views}, 4, 'counts logged views');
is($summary->{popular}[0]{id}, 'a', 'sorts popular articles by views');
is($summary->{popular}[0]{views}, 2, 'counts popular article views');

remove_tree($root);
done_testing;
