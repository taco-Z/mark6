package boot;
use strict;
use warnings;
use utf8;

use Cwd qw(abs_path);
use FindBin;
use lang ();
use web ();

sub init {
    my %query_params = %{ web::parse_params($ENV{QUERY_STRING} // '') };
    my %body_params  = ();
    my %params       = ();
    my %cookies      = %{ web::parse_cookies($ENV{HTTP_COOKIE} // '') };
    my $base_dir     = abs_path($FindBin::Bin) || $FindBin::Bin;

    if (uc($ENV{REQUEST_METHOD} || '') eq 'POST') {
        %body_params = %{ web::read_post_params() };
    }

    %params = (%query_params, %body_params);

    my $ctx = {
        env      => { %ENV },
        params   => \%params,
        base_dir => $base_dir,
        cookies  => \%cookies,
    };

    my $lang = lang::detect_lang(
        query_params  => \%query_params,
        cookies       => \%cookies,
        default_lang  => 'en',
    );

    $ctx->{lang} = $lang;
    $ctx->{dict} = lang::load_dict($base_dir, $lang);

    return $ctx;
}

1;

