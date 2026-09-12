use strict;
use warnings;
use Test::More;
use File::Path qw(make_path remove_tree);
use File::Spec;
use JSON::PP ();

use lib 'lib';
use Mark6::Stats;

my $root = File::Spec->catdir('t', 'tmp_stats');
remove_tree($root) if -d $root;
make_path(File::Spec->catdir($root, 'dat', 'logs'));

my $log_path = File::Spec->catfile($root, 'dat', 'logs', 'access.jsonl');
write_jsonl($log_path,
    event(day_offset => -10, route => 'index', traffic => 'human'),
    event(day_offset => -1, route => 'article', article_id => 'old-week', article_title => 'Old Week', traffic => 'human'),
    event(day_offset => 0, route => 'index', traffic => 'human'),
    event(day_offset => 0, route => 'node'),
    event(day_offset => 0, route => 'article', article_id => 'today-article', article_title => 'Today Article', traffic => 'human'),
    event(day_offset => 0, route => 'article', article_id => 'legacy-article', article_title => 'Legacy Article'),
);

open my $append, '>>:raw', $log_path or die "Cannot append $log_path: $!";
print {$append} "not json\n";
close $append;

my $summary = Mark6::Stats->new(root => $root)->access_summary();

is($summary->{today_views}, 2, 'counts only today index and article page views');
is($summary->{week_views}, 3, 'counts recent page views separately from total');
is($summary->{total_views}, 4, 'counts all page views across the full access log');
is($summary->{legacy_views}, 1, 'keeps unclassified legacy page views separate from filtered totals');

my %popular = map { $_->{id} => $_->{views} } @{$summary->{popular}};
is($popular{'today-article'}, 1, 'popular articles include article page views');
is($popular{'old-week'}, 1, 'popular articles include older article page views');
ok(!exists $popular{''}, 'non-article and node events are not popular article rows');

remove_tree($root);
done_testing;

sub event {
    my (%args) = @_;
    my $day = day($args{day_offset} || 0);
    return {
        kind          => 'page',
        at            => "${day}T00:00:00Z",
        day           => $day,
        lang          => 'ja',
        route          => $args{route},
        article_id    => $args{article_id} || '',
        article_title => $args{article_title} || '',
        (defined $args{traffic} ? (traffic => $args{traffic}) : ()),
    };
}

sub day {
    my ($offset) = @_;
    my @t = gmtime(time + $offset * 24 * 60 * 60);
    return sprintf('%04d-%02d-%02d', $t[5] + 1900, $t[4] + 1, $t[3]);
}

sub write_jsonl {
    my ($path, @events) = @_;
    open my $fh, '>:raw', $path or die "Cannot write $path: $!";
    my $json = JSON::PP->new->utf8->canonical;
    for my $event (@events) {
        print {$fh} $json->encode($event), "\n";
    }
    close $fh;
}
