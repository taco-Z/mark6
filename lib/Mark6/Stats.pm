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
    my $popular_limit = $args{popular_limit} || 5000;
    my $path = "$self->{root}/dat/logs/access.jsonl";
    return _empty_summary() unless -f $path;

    open my $fh, '<:raw', $path or return _empty_summary();

    my $today = _day(time);
    my $week_start = _day(time - 6 * 24 * 60 * 60);
    my (%article_views, %article_titles);
    my ($today_views, $week_views, $total, $legacy_views) = (0, 0, 0, 0);
    my @article_events;

    while (my $line = <$fh>) {
        my $event = eval { decode_json($line) } || next;
        next unless ($event->{kind} || '') eq 'page';
        next unless _is_trackable_route($event);
        if (($event->{traffic} || '') ne 'human') {
            $legacy_views++;
            next;
        }
        my $day = $event->{day} || '';
        $total++;
        $today_views++ if $day eq $today;
        $week_views++ if $day ge $week_start && $day le $today;
        next unless ($event->{article_id} || '') ne '';
        push @article_events, $event;
    }
    close $fh;

    @article_events = @article_events[-$popular_limit .. -1] if @article_events > $popular_limit;
    for my $event (@article_events) {
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
        legacy_views => $legacy_views,
        popular     => \@popular,
    };
}

sub _empty_summary {
    return { today_views => 0, week_views => 0, total_views => 0, legacy_views => 0, popular => [] };
}

sub _is_trackable_route {
    my ($event) = @_;
    my $route = $event->{route} || 'index';
    return $route eq 'index' || $route eq 'article';
}

sub _day {
    my ($epoch) = @_;
    my @t = gmtime($epoch);
    return sprintf('%04d-%02d-%02d', $t[5] + 1900, $t[4] + 1, $t[3]);
}

1;
