package render;
use strict;
use warnings;
use utf8;

sub render {
    my ($ctx, $template_path, $data) = @_;
    $data ||= {};

    my $file = $ctx->{path}->{tpl_dir} . '/' . $template_path;

    open my $fh, '<:utf8', $file or die "Cannot open template $file: $!";
    local $/;
    my $html = <$fh>;
    close $fh;

    for my $key (keys %{$data}) {
        my $val = defined $data->{$key} ? $data->{$key} : '';
        $html =~ s/\{\{\Q$key\E\}\}/$val/g;
    }

    $html =~ s/\{\{[a-zA-Z0-9_]+\}\}//g;

    return $html;
}

sub h {
    my ($s) = @_;
    $s = '' unless defined $s;

    $s =~ s/&/&amp;/g;
    $s =~ s/</&lt;/g;
    $s =~ s/>/&gt;/g;
    $s =~ s/"/&quot;/g;
    $s =~ s/'/&#39;/g;

    return $s;
}

1;
