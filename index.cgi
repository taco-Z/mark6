#!/usr/bin/perl
use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/lib";

use boot;
use article;
use render;
use web;

binmode STDOUT, ':encoding(UTF-8)';

my $ctx = boot::init('public');
my $id  = $ctx->{params}->{id} || '';

my $html;

if ($id) {
    my $row = article::get_article($ctx, $id);
    if ($row && $row->{status}) {
        $html = render::render($ctx, 'public/article.html', {
            site_title => render::h($ctx->{config}->{site_title}),
            title      => render::h($row->{title} || ''),
            body       => $row->{body} || '',
            category   => render::h($row->{category} || ''),
            created    => render::h($row->{created} || ''),
        });
    } else {
        $html = 'Not Found';
    }
} else {
    my $rows = article::list_articles($ctx);
    my $list_html = '';

    for my $row (@$rows) {
        next unless $row->{status};
        my $title = render::h($row->{title} || '');
        my $aid   = render::h($row->{id} || '');
        $list_html .= qq{<li><a href="index.cgi?id=$aid">$title</a></li>\n};
    }

    $html = render::render($ctx, 'public/index.html', {
        site_title   => render::h($ctx->{config}->{site_title}),
        article_list => $list_html,
    });
}

print web::header_html();
print $html;
