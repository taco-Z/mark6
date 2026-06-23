package Mark6::Stats;

use strict;
use warnings;
use JSON::PP qw(decode_json);

sub new {
    my ($class, %args) = @_;
    return bless {
        root => $args{root} || '.',
    }, $class;
}

sub access_summary {
    my ($self, %args) = @_;
    my $limit = $args{limit} || 5000;
    my $path = "$self->{root}/dat/logs/access.jsonl";
    return _empty_summary() unless -f $path;

    open my $fh, '<:raw', $path or return _empty_summary();
    my $size = -s $fh || 0;
    if ($size > 512 * 1024) {
        seek($fh, -512 * 1024, 2);
        <$fh>; # Discard the first partial JSON line after seeking.
    }
    my @events = <$fh>;
    close $fh;
    @events = @events[-$limit .. -1] if @events > $limit;

    my $today = _day(time);
    my $week_start = _day(time - 6 * 24 * 60 * 60);
    my (%article_views, %article_titles);
    my ($today_views, $week_views, $total) = (0, 0, 0);

    for my $line (@events) {
        my $event = eval { decode_json($line) } || next;
        next unless ($event->{kind} || '') eq 'page';
        my $day = $event->{day} || '';
        $total++;
        $today_views++ if $day eq $today;
        $week_views++ if $day ge $week_start && $day le $today;
        next unless ($event->{article_id} || '') ne '';
        $article_views{$event->{article_id}}++;
        $article_titles{$event->{article_id}} = $event->{article_title} || $event->{article_id};
    }

    my @popular = map {
        { id => $_, title => $article_titles{$_}, views => $article_views{$_} }
    } sort {
        $article_views{$b} <=> $article_views{$a} || $a cmp $b
    } keys %article_views;
    @popular = @popular[0 .. 4] if @popular > 5;

    return {
        today_views => $today_views,
        week_views  => $week_views,
        total_views => $total,
        popular     => \@popular,
    };
}

sub _empty_summary {
    return { today_views => 0, week_views => 0, total_views => 0, popular => [] };
}

sub _day {
    my ($epoch) = @_;
    my @t = gmtime($epoch);
    return sprintf('%04d-%02d-%02d', $t[5] + 1900, $t[4] + 1, $t[3]);
}

1;
