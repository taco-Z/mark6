package Mark6::DataStore;

use strict;
use warnings;
use JSON::PP qw(decode_json encode_json);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use Fcntl qw(:flock);

sub new {
    my ($class, %args) = @_;
    my $root = $args{root} || '.';

    return bless {
        root => $root,
        json => JSON::PP->new->utf8->canonical->pretty,
    }, $class;
}

sub root {
    my ($self) = @_;
    return $self->{root};
}

sub path {
    my ($self, @parts) = @_;
    return join('/', $self->{root}, @parts);
}

sub read_json {
    my ($self, @parts) = @_;
    my $path = $self->path(@parts);
    return undef unless -e $path;

    open my $fh, '<:raw', $path or die "Cannot read $path: $!";
    local $/;
    my $body = <$fh>;
    close $fh;

    return decode_json($body);
}

sub write_json {
    my ($self, $data, @parts) = @_;
    my $path = $self->path(@parts);
    my $dir = dirname($path);
    make_path($dir) unless -d $dir;

    my $tmp = "$path.tmp.$$";
    open my $fh, '>:raw', $tmp or die "Cannot write $tmp: $!";
    flock($fh, LOCK_EX) or die "Cannot lock $tmp: $!";
    print {$fh} $self->{json}->encode($data);
    close $fh or die "Cannot close $tmp: $!";

    rename $tmp, $path or die "Cannot move $tmp to $path: $!";
    return $path;
}

sub append_jsonl {
    my ($self, $data, @parts) = @_;
    my $path = $self->path(@parts);
    my $dir = dirname($path);
    make_path($dir) unless -d $dir;

    open my $fh, '>>:raw', $path or die "Cannot append $path: $!";
    flock($fh, LOCK_EX) or die "Cannot lock $path: $!";
    print {$fh} JSON::PP->new->utf8->canonical->encode($data), "\n";
    close $fh;

    return $path;
}

1;

