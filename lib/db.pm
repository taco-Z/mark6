package db;
use strict;
use warnings;
use utf8;

use JSON::PP ();

sub load_json {
    my ($file) = @_;
    return {} unless -f $file;

    open my $fh, '<:utf8', $file or die "Cannot open $file: $!";
    local $/;
    my $json = <$fh>;
    close $fh;

    return {} unless defined $json && length $json;
    return JSON::PP::decode_json($json);
}

sub save_json {
    my ($file, $data) = @_;

    open my $fh, '>:utf8', $file or die "Cannot write $file: $!";
    print {$fh} JSON::PP->new->utf8(0)->canonical(1)->pretty(1)->encode($data);
    close $fh;

    return 1;
}

sub load_jsonl {
    my ($file) = @_;
    my @rows;

    return [] unless -f $file;

    open my $fh, '<:utf8', $file or die "Cannot open $file: $!";
    while (my $line = <$fh>) {
        chomp $line;
        next unless $line =~ /\S/;
        push @rows, JSON::PP::decode_json($line);
    }
    close $fh;

    return \@rows;
}

sub append_jsonl {
    my ($file, $record) = @_;

    open my $fh, '>>:utf8', $file or die "Cannot append $file: $!";
    print {$fh} JSON::PP::encode_json($record) . "\n";
    close $fh;

    return 1;
}

sub save_jsonl {
    my ($file, $rows) = @_;

    open my $fh, '>:utf8', $file or die "Cannot write $file: $!";
    for my $row (@{$rows || []}) {
        print {$fh} JSON::PP::encode_json($row) . "\n";
    }
    close $fh;

    return 1;
}

1;
