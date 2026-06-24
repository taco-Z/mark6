#!/usr/bin/env perl

use strict;
use warnings;
use utf8;
use Digest::SHA qw(sha1_hex);
use File::Path qw(make_path);
use File::Spec;
use Getopt::Long qw(GetOptions);
use JSON::PP ();
use Time::Piece;

my %args = (
    node => 'oita360',
);
my @skip_video_ids;

GetOptions(
    'csv=s'           => \$args{csv},
    'output=s'        => \$args{output},
    'node=s'          => \$args{node},
    'skip-video-id=s' => \@skip_video_ids,
    'force'           => \$args{force},
) or usage();

usage() unless $args{csv} && $args{output};
die "Invalid node\n" unless $args{node} =~ /\A[0-9A-Za-z_-]+\z/;

my %skip = map { $_ => 1 } @skip_video_ids;
my $rows = read_youtube_csv($args{csv});
make_path($args{output}) unless -d $args{output};

my ($created, $skipped) = (0, 0);
for my $row (@{$rows}) {
    my $video_id = $row->{'コンテンツ'} || '';
    next unless $video_id =~ /\A[0-9A-Za-z_-]{11}\z/;

    if ($skip{$video_id}) {
        $skipped++;
        next;
    }

    my $id = article_id_for($video_id);
    my $path = File::Spec->catfile($args{output}, "$id.json");
    if (-e $path && !$args{force}) {
        $skipped++;
        next;
    }

    my $title = $row->{'動画のタイトル'} || "YouTube $video_id";
    my $published_at = iso_date($row->{'動画公開時刻'} || '');
    my $body = youtube_embed($video_id, $title);
    my $article = {
        id                 => $id,
        type               => 'article',
        status             => 'draft',
        default_lang       => 'ja',
        node               => $args{node},
        slug               => "video-$video_id",
        tags               => ['OITA360', 'YouTube'],
        image              => "https://img.youtube.com/vi/$video_id/hqdefault.jpg",
        langs              => {
            ja => { title => $title, description => '', body => $body },
            en => { title => '', description => '', body => '' },
        },
        translation_status => {
            ja => { state => 'source',       updated_at => $published_at },
            en => { state => 'untranslated', updated_at => '' },
        },
        title              => $title,
        intro              => '',
        body               => $body,
        writer_id          => '',
        created_at         => $published_at,
        updated_at         => $published_at,
        youtube            => {
            video_id        => $video_id,
            url             => "https://www.youtube.com/watch?v=$video_id",
            published_at    => $published_at,
            duration_seconds => 0 + ($row->{'長さ'} || 0),
        },
    };

    write_json($path, $article);
    $created++;
}

print "Created $created draft article JSON file(s); skipped $skipped.\n";

sub read_youtube_csv {
    my ($path) = @_;
    open my $fh, '<:encoding(UTF-8)', $path or die "Cannot open $path: $!\n";
    my $header = <$fh>;
    die "CSV is empty\n" unless defined $header;
    chomp $header;
    $header =~ s/\r\z//;
    my @columns = parse_csv_line($header);
    my @rows;

    while (my $line = <$fh>) {
        chomp $line;
        $line =~ s/\r\z//;
        next if $line eq '';
        my @values = parse_csv_line($line);
        my %row;
        @row{@columns} = @values;
        push @rows, \%row;
    }

    close $fh;
    return \@rows;
}

sub parse_csv_line {
    my ($line) = @_;
    my (@values, $value, $quoted) = ();
    my $index = 0;

    while ($index < length $line) {
        my $char = substr($line, $index, 1);
        if ($quoted) {
            if ($char eq '"') {
                if (substr($line, $index + 1, 1) eq '"') {
                    $value .= '"';
                    $index += 2;
                    next;
                }
                $quoted = 0;
            }
            else {
                $value .= $char;
            }
        }
        elsif ($char eq '"' && $value eq '') {
            $quoted = 1;
        }
        elsif ($char eq ',') {
            push @values, $value;
            $value = '';
        }
        else {
            $value .= $char;
        }
        $index++;
    }

    push @values, $value;
    return @values;
}

sub article_id_for {
    my ($video_id) = @_;
    return 2_000_000_000 + (hex(substr(sha1_hex($video_id), 0, 7)) % 900_000_000);
}

sub iso_date {
    my ($value) = @_;
    return Time::Piece->gmtime->strftime('%Y-%m-%dT%H:%M:%SZ') unless $value;
    my $time = Time::Piece->strptime($value, '%b %d, %Y');
    return $time->strftime('%Y-%m-%dT00:00:00Z');
}

sub youtube_embed {
    my ($video_id, $title) = @_;
    $title =~ s/&/&amp;/g;
    $title =~ s/"/&quot;/g;
    $title =~ s/</&lt;/g;
    $title =~ s/>/&gt;/g;
    return qq|<iframe width="560" height="315" src="https://www.youtube.com/embed/$video_id" title="$title" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>|;
}

sub write_json {
    my ($path, $data) = @_;
    open my $fh, '>:raw', $path or die "Cannot write $path: $!\n";
    print {$fh} JSON::PP->new->utf8->canonical->pretty->encode($data);
    close $fh;
}

sub usage {
    die <<'USAGE';
Usage:
  perl tools/import_youtube_csv.pl --csv table.csv --output dat/articles --node oita360 \
    --skip-video-id Jce1N0hRfJc --skip-video-id 4oNRjqXyjz0

Creates draft MARK6 article JSON files from a YouTube Analytics table CSV.
Existing output files are skipped unless --force is supplied.
USAGE
}
