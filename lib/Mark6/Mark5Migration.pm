package Mark6::Mark5Migration;

use strict;
use warnings;
use JSON::PP ();
use Encode qw(FB_CROAK decode);
use File::Basename qw(dirname);
use File::Copy qw(copy);
use File::Find qw(find);
use File::Path qw(make_path);
use File::Spec;
use Mark6::DataStore;

sub new {
    my ($class, %args) = @_;
    die "--from is required" unless $args{from};
    die "--to is required" unless $args{to};

    return bless {
        from   => $args{from},
        to     => $args{to},
        store  => Mark6::DataStore->new(root => $args{to}),
        report => {
            warnings => [],
            written  => [],
            copied   => [],
            skipped  => [],
        },
    }, $class;
}

sub run {
    my ($self) = @_;

    $self->_ensure_dirs;
    $self->_migrate_config;
    $self->_migrate_home;
    $self->_migrate_articles;
    $self->_migrate_shop_articles;
    $self->_migrate_users;
    $self->_migrate_logs;
    $self->_copy_tree('img', 'img');
    $self->_copy_tree('file', 'file');
    $self->_write_report;

    return $self->{report};
}

sub _ensure_dirs {
    my ($self) = @_;
    for my $dir (
        'dat/articles',
        'dat/shop_articles',
        'dat/logs',
        'dat/legacy/mark5',
        'file',
        'img',
    ) {
        my $path = File::Spec->catdir($self->{to}, split('/', $dir));
        make_path($path) unless -d $path;
    }
}

sub _migrate_config {
    my ($self) = @_;
    my $rows = $self->_read_kv_file('dat/ini.cgi');

    if (!%{$rows}) {
        $self->_warn_missing('dat/ini.cgi');
        return;
    }

    my $config = {
        version => 1,
        site => {
            title    => $rows->{site_title} || 'MARK6 Site',
            base_url => '',
            language => 'ja',
        },
        features => {
            tags    => _bool($rows->{tag_sw}),
            newest  => _bool($rows->{news_sw}),
            popular => _bool($rows->{rank_sw}),
            shop    => _bool($rows->{shop_sw}),
            ai      => 0,
        },
        display => {
            articles_per_page => 20,
            mini_articles     => _number($rows->{number_miniart}, 15),
        },
        shop => {
            title     => $rows->{shop_title} || 'Shop',
            paypal_id => $rows->{paypal_id} || '',
        },
    };

    $self->_write_json($config, 'dat/config.json');
}

sub _migrate_home {
    my ($self) = @_;
    my $rows = $self->_read_kv_file('dat/index.cgi');

    if (!%{$rows}) {
        $self->_warn_missing('dat/index.cgi');
        return;
    }

    my $home = {
        title         => $rows->{title} || 'Home',
        body          => $rows->{body} || '',
        show_articles => _bool($rows->{index_sw}),
        updated_at    => '',
    };

    $self->_write_json($home, 'dat/home.json');
}

sub _migrate_articles {
    my ($self) = @_;
    my $lines = $self->_read_lines('dat/article.cgi');

    if (!@{$lines}) {
        $self->_warn_missing('dat/article.cgi');
        return;
    }

    my $count = 0;
    for my $line (@{$lines}) {
        next if $line =~ /^\s*$/;
        my ($id, $tags, $pic, $title, $intro, $body, $writer, $admit) = split(/==/, $line, 8);
        next unless defined $id && $id ne '';

        my $article = {
            id         => "$id",
            type       => 'article',
            status     => _bool($admit) ? 'published' : 'draft',
            title      => _decode_mark5($title),
            slug       => '',
            tags       => _tags($tags),
            image      => _decode_mark5($pic),
            intro      => _decode_mark5($intro),
            body       => _decode_mark5($body),
            writer_id  => _decode_mark5($writer),
            created_at => _epoch_to_iso($id),
            updated_at => '',
            ai => {
                summary           => '',
                suggested_tags    => [],
                seo_description   => '',
                last_processed_at => '',
            },
            source => {
                mark5_id   => "$id",
                mark5_line => $line,
            },
        };

        $self->_write_json($article, "dat/articles/$id.json");
        $count++;
    }

    push @{$self->{report}{written}}, "articles: $count";
}

sub _migrate_shop_articles {
    my ($self) = @_;
    my $lines = $self->_read_lines('dat/shop_article.cgi');

    if (!@{$lines}) {
        $self->_warn_missing('dat/shop_article.cgi');
        return;
    }

    my $count = 0;
    for my $line (@{$lines}) {
        next if $line =~ /^\s*$/;
        my ($id, $tags, $pic, $title, $intro, $body, $price, $stock, $admit) = split(/==/, $line, 9);
        next unless defined $id && $id ne '';

        my $product = {
            id         => "$id",
            type       => 'shop_article',
            status     => _bool($admit) ? 'published' : 'draft',
            title      => _decode_mark5($title),
            slug       => '',
            tags       => _tags($tags),
            image      => _decode_mark5($pic),
            intro      => _decode_mark5($intro),
            body       => _decode_mark5($body),
            price      => _number(_decode_mark5($price), 0),
            stock      => _number($stock, 0),
            created_at => _epoch_to_iso($id),
            updated_at => '',
            source => {
                mark5_id   => "$id",
                mark5_line => $line,
            },
        };

        $self->_write_json($product, "dat/shop_articles/$id.json");
        $count++;
    }

    push @{$self->{report}{written}}, "shop_articles: $count";
}

sub _migrate_users {
    my ($self) = @_;
    my $lines = $self->_read_lines('dat/user.cgi');

    if (!@{$lines}) {
        $self->_warn_missing('dat/user.cgi');
        return;
    }

    my @users;
    for my $line (@{$lines}) {
        next if $line =~ /^\s*$/;
        my ($id, $rank, $user, $hash) = split(/==/, $line, 4);
        next unless defined $id && $id ne '';

        push @users, {
            id                      => "$id",
            name                    => _decode_mark5($user),
            rank                    => _decode_mark5($rank) || 'writer',
            password_hash           => '',
            legacy_password_hash    => _decode_mark5($hash),
            password_reset_required => JSON::PP::true,
            created_at              => _epoch_to_iso($id),
            updated_at              => '',
        };
    }

    $self->_write_json({ version => 1, users => \@users }, 'dat/users.json');
}

sub _migrate_logs {
    my ($self) = @_;
    $self->_archive_raw('dat/access_log.cgi');
    $self->_archive_raw('dat/login_log.cgi');
}

sub _copy_tree {
    my ($self, $source_name, $target_name) = @_;
    my $source = File::Spec->catdir($self->{from}, $source_name);
    my $target = File::Spec->catdir($self->{to}, $target_name);

    if (!-d $source) {
        push @{$self->{report}{skipped}}, "$source_name/: not found";
        return;
    }

    find({
        wanted => sub {
            return if -d $_;
            my $rel = File::Spec->abs2rel($File::Find::name, $source);
            my $dst = File::Spec->catfile($target, $rel);
            make_path(dirname($dst));
            copy($File::Find::name, $dst) or die "Cannot copy $File::Find::name to $dst: $!";
            push @{$self->{report}{copied}}, "$source_name/$rel";
        },
        no_chdir => 1,
    }, $source);
}

sub _archive_raw {
    my ($self, $relative) = @_;
    my $source = File::Spec->catfile($self->{from}, split('/', $relative));
    return unless -e $source;

    my $target = File::Spec->catfile($self->{to}, 'dat', 'legacy', 'mark5', (split('/', $relative))[-1]);
    copy($source, $target) or die "Cannot archive $source to $target: $!";
    push @{$self->{report}{copied}}, "legacy/$relative";
}

sub _write_json {
    my ($self, $data, $relative) = @_;
    $self->{store}->write_json($data, split('/', $relative));
    push @{$self->{report}{written}}, $relative;
}

sub _write_report {
    my ($self) = @_;
    $self->{store}->write_json($self->{report}, 'dat/migration_report.json');
}

sub _read_kv_file {
    my ($self, $relative) = @_;
    my %rows;
    for my $line (@{$self->_read_lines($relative)}) {
        next if $line =~ /^\s*$/;
        my ($key, $value) = split(/==/, $line, 2);
        next unless defined $key && $key ne '';
        $rows{$key} = _decode_mark5($value);
    }
    return \%rows;
}

sub _read_lines {
    my ($self, $relative) = @_;
    my $path = File::Spec->catfile($self->{from}, split('/', $relative));
    return [] unless -e $path;

    open my $fh, '<:raw', $path or die "Cannot read $path: $!";
    local $/;
    my $raw = <$fh>;
    close $fh;

    my @raw_lines = split(/\r\n|\n|\r/, $raw);
    my @lines = map { _decode_text_line($_) } @raw_lines;
    return \@lines;
}

sub _warn_missing {
    my ($self, $relative) = @_;
    push @{$self->{report}{warnings}}, "$relative not found or empty";
}

sub _decode_mark5 {
    my ($value) = @_;
    return '' unless defined $value;
    $value =~ s/<equal>/=/g;
    $value =~ s/<br>/\n/g;
    $value =~ s/<return>/\n/g;
    return $value;
}

sub _decode_text_line {
    my ($raw) = @_;
    my $text;
    eval { $text = decode('UTF-8', $raw, FB_CROAK); 1 }
        or $text = decode('CP932', $raw);
    return $text;
}

sub _tags {
    my ($value) = @_;
    $value = _decode_mark5($value);
    return [] if $value eq '';

    my @tags = grep { $_ ne '' } map {
        my $tag = $_;
        $tag =~ s/^\s+|\s+$//g;
        $tag;
    } split(/,/, $value);

    return \@tags;
}

sub _bool {
    my ($value) = @_;
    return JSON::PP::true if defined $value && $value =~ /^(1|true|yes|on)$/i;
    return JSON::PP::false;
}

sub _number {
    my ($value, $fallback) = @_;
    return $fallback unless defined $value && $value =~ /^-?\d+(?:\.\d+)?$/;
    return 0 + $value;
}

sub _epoch_to_iso {
    my ($value) = @_;
    return '' unless defined $value && $value =~ /^\d+$/;
    my @t = gmtime($value);
    return sprintf('%04d-%02d-%02dT%02d:%02d:%02dZ',
        $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0]);
}

1;
