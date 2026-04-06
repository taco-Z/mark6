package boot;
use strict;
use warnings;
use utf8;

use JSON::PP ();
use File::Spec;
use FindBin;
use web;

sub init {
    my ($mode) = @_;
    $mode ||= 'public';

    my $root   = File::Spec->rel2abs($FindBin::Bin);
    my $dat    = File::Spec->catdir($root, 'dat');
    my $tpl    = File::Spec->catdir($root, 'template');
    my $lib    = File::Spec->catdir($root, 'lib');
    my $tmp    = File::Spec->catdir($root, 'tmp');
    my $static = File::Spec->catdir($root, 'static');

    my $config_file = File::Spec->catfile($dat, 'config.json');

    my $config = {
        site_title        => 'MARK6',
        site_url          => '',
        article_page_size => 20,
        session_hours     => 12,
        cookie_name       => 'mark6_sid',
    };

    if (-f $config_file) {
        open my $fh, '<:utf8', $config_file or die "Cannot open $config_file: $!";
        local $/;
        my $json = <$fh>;
        close $fh;

        if (defined $json && $json =~ /\S/) {
            my $loaded = eval { JSON::PP::decode_json($json) };
            die "Invalid JSON in $config_file: $@" if $@;
            $config = { %{$config}, %{$loaded || {}} };
        }
    }

    return {
        mode    => $mode,
        now     => time,
        params  => web::parse_params(),
        cookies => web::parse_cookies(),
        config  => $config,
        path    => {
            root       => $root,
            dat_dir    => $dat,
            tpl_dir    => $tpl,
            lib_dir    => $lib,
            tmp_dir    => $tmp,
            static_dir => $static,
            article_db => File::Spec->catfile($dat, 'article.jsonl'),
            user_db    => File::Spec->catfile($dat, 'user.jsonl'),
            session_db => File::Spec->catfile($dat, 'session.jsonl'),
            config     => $config_file,
        },
    };
}

1;
