package article;
use strict;
use warnings;
use utf8;

use db;

sub list_articles {
    my ($ctx) = @_;
    my $rows = db::load_jsonl($ctx->{path}->{article_db});

    my @sorted = sort {
        ($b->{created} || 0) <=> ($a->{created} || 0)
    } @$rows;

    return \@sorted;
}

sub get_article {
    my ($ctx, $id) = @_;
    return undef unless defined $id && length $id;

    my $rows = db::load_jsonl($ctx->{path}->{article_db});
    for my $row (@$rows) {
        return $row if ($row->{id} // '') eq $id;
    }
    return undef;
}

sub save_article {
    my ($ctx, $data) = @_;

    my $rows = db::load_jsonl($ctx->{path}->{article_db});
    my $id   = $data->{id} || _new_id($ctx);

    my $found = 0;
    for my $row (@$rows) {
        next unless ($row->{id} // '') eq $id;
        $row->{title}    = $data->{title};
        $row->{body}     = $data->{body};
        $row->{category} = $data->{category};
        $row->{status}   = $data->{status};
        $row->{updated}  = $ctx->{now};
        $found = 1;
    }

    if (!$found) {
        push @$rows, {
            id       => $id,
            title    => $data->{title},
            body     => $data->{body},
            category => $data->{category},
            status   => $data->{status},
            created  => $ctx->{now},
            updated  => $ctx->{now},
        };
    }

    db::save_jsonl($ctx->{path}->{article_db}, $rows);
    return $id;
}

sub delete_article {
    my ($ctx, $id) = @_;
    my $rows = db::load_jsonl($ctx->{path}->{article_db});
    my @keep = grep { ($_->{id} // '') ne $id } @$rows;
    db::save_jsonl($ctx->{path}->{article_db}, \@keep);
    return 1;
}

sub _new_id {
    my ($ctx) = @_;
    return $ctx->{now} . int(rand(1000));
}

1;