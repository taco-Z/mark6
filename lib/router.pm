package router;
use strict;
use warnings;
use utf8;
use JSON::PP;
use lang qw(load_dict get_lang t);
use render ();

sub dispatch_admin {
    my ($ctx) = @_;

    $ctx ||= {};
    $ctx->{env}    ||= \%ENV;
    $ctx->{params} ||= _parse_query_string($ctx->{env}->{QUERY_STRING} // '');

    # lang dict
    $ctx->{lang_file} ||= 'dat/lang/admin.json';
    $ctx->{lang_dict} ||= lang::load_dict($ctx->{lang_file});
    $ctx->{lang}      ||= lang::get_lang($ctx);

    my $cookie_line = '';
    if (defined $ctx->{params}->{lang} && _is_allowed_lang($ctx->{params}->{lang}, $ctx->{lang_dict})) {
        $cookie_line = _build_lang_cookie_header($ctx->{params}->{lang});
        $ctx->{lang} = $ctx->{params}->{lang};
    }

    my $mode = $ctx->{params}->{mode} || '';

    if ($mode eq 'login' && _is_post($ctx)) {
        return _do_login($ctx, $cookie_line);
    }
    elsif ($mode eq 'logout') {
        return _logout($ctx, $cookie_line);
    }
    elsif ($mode eq 'edit') {
        return _show_article_edit($ctx, $cookie_line);
    }
    elsif ($mode eq 'save' && _is_post($ctx)) {
        return _save_article($ctx, $cookie_line);
    }
    elsif ($mode eq 'delete') {
        return _delete_article($ctx, $cookie_line);
    }
    elsif (_is_logged_in($ctx)) {
        return _show_admin_home($ctx, $cookie_line);
    }
    else {
        return _show_login($ctx, $cookie_line);
    }
}

sub _show_login {
    my ($ctx, $cookie_line) = @_;

    my $vars = {
        page_title      => lang::t($ctx, 'login_title'),
        login_title     => lang::t($ctx, 'login_title'),
        login_desc      => lang::t($ctx, 'login_desc'),
        login_button    => lang::t($ctx, 'login_button'),
        username_label  => lang::t($ctx, 'username_label'),
        password_label  => lang::t($ctx, 'password_label'),
        lang_ja_url     => _build_lang_url($ctx, 'ja'),
        lang_en_url     => _build_lang_url($ctx, 'en'),
        message         => '',
    };

    my $html = render::render_template('template/admin/login.html', $vars);
    return _print_html_response(
        body        => $html,
        cookie_line => $cookie_line,
    );
}

sub _show_admin_home {
    my ($ctx, $cookie_line) = @_;

    my $articles = _load_jsonl('dat/article.jsonl');

    my $article_rows = '';
    for my $row (@$articles) {
        my $id    = _html_escape($row->{id}    // '');
        my $title = _html_escape($row->{title} // '');
        my $stat  = _html_escape($row->{status} // '');

        $article_rows .= qq{<tr>}
                       . qq{<td>$id</td>}
                       . qq{<td>$title</td>}
                       . qq{<td>$stat</td>}
                       . qq{<td><a href="?mode=edit&id=$id&lang=$ctx->{lang}">Edit</a></td>}
                       . qq{</tr>\n};
    }

    if ($article_rows eq '') {
        $article_rows = qq{<tr><td colspan="4">} . _html_escape(lang::t($ctx, 'no_articles')) . qq{</td></tr>};
    }

    my $vars = {
        page_title        => lang::t($ctx, 'admin_title'),
        admin_title       => lang::t($ctx, 'admin_title'),
        article_list      => lang::t($ctx, 'article_list'),
        new_article       => lang::t($ctx, 'new_article'),
        logout_label      => lang::t($ctx, 'logout_label'),
        article_rows      => $article_rows,
        lang_ja_url       => _build_lang_url($ctx, 'ja'),
        lang_en_url       => _build_lang_url($ctx, 'en'),
        new_article_url   => '?mode=edit&lang=' . $ctx->{lang},
        logout_url        => '?mode=logout&lang=' . $ctx->{lang},
    };

    my $html = render::render_template('template/admin/index.html', $vars);
    return _print_html_response(
        body        => $html,
        cookie_line => $cookie_line,
    );
}

sub _show_article_edit {
    my ($ctx, $cookie_line) = @_;

    my $id = $ctx->{params}->{id} || '';
    my $article = {};

    if (length $id) {
        my $rows = _load_jsonl('dat/article.jsonl');
        for my $row (@$rows) {
            if (($row->{id} // '') eq $id) {
                $article = $row;
                last;
            }
        }
    }

    my $vars = {
        page_title      => lang::t($ctx, 'edit_article'),
        edit_title      => lang::t($ctx, 'edit_article'),
        title_label     => lang::t($ctx, 'title_label'),
        body_label      => lang::t($ctx, 'body_label'),
        status_label    => lang::t($ctx, 'status_label'),
        save_button     => lang::t($ctx, 'save_button'),
        back_label      => lang::t($ctx, 'back_label'),
        id              => _html_escape($article->{id} // ''),
        title           => _html_escape($article->{title} // ''),
        body            => _html_escape($article->{body} // ''),
        status          => _html_escape($article->{status} // 'draft'),
        back_url        => '?lang=' . $ctx->{lang},
        form_action     => '?mode=save&lang=' . $ctx->{lang},
    };

    my $html = render::render_template('template/admin/edit.html', $vars);
    return _print_html_response(
        body        => $html,
        cookie_line => $cookie_line,
    );
}

sub _save_article {
    my ($ctx, $cookie_line) = @_;

    my $body_params = _parse_post_body($ctx);
    my $id     = $body_params->{id}     // '';
    my $title  = $body_params->{title}  // '';
    my $body   = $body_params->{body}   // '';
    my $status = $body_params->{status} // 'draft';

    my $rows = _load_jsonl('dat/article.jsonl');

    if (!length $id) {
        $id = _next_article_id($rows);
        push @$rows, {
            id     => $id,
            title  => $title,
            body   => $body,
            status => $status,
        };
    } else {
        my $found = 0;
        for my $row (@$rows) {
            next unless ($row->{id} // '') eq $id;
            $row->{title}  = $title;
            $row->{body}   = $body;
            $row->{status} = $status;
            $found = 1;
            last;
        }
        if (!$found) {
            push @$rows, {
                id     => $id,
                title  => $title,
                body   => $body,
                status => $status,
            };
        }
    }

    _save_jsonl('dat/article.jsonl', $rows);

    return _redirect('?lang=' . $ctx->{lang}, $cookie_line);
}

sub _delete_article {
    my ($ctx, $cookie_line) = @_;

    my $id = $ctx->{params}->{id} || '';
    my $rows = _load_jsonl('dat/article.jsonl');

    my @kept = grep { ($_->{id} // '') ne $id } @$rows;
    _save_jsonl('dat/article.jsonl', \@kept);

    return _redirect('?lang=' . $ctx->{lang}, $cookie_line);
}

sub _do_login {
    my ($ctx, $cookie_line) = @_;

    my $body_params = _parse_post_body($ctx);
    my $username = $body_params->{username} // '';
    my $password = $body_params->{password} // '';

    # 仮実装: admin / mark6
    if ($username eq 'admin' && $password eq 'mark6') {
        my $session_cookie = _build_session_cookie_header('dummy_session_ok');

        my $html = qq{
<!DOCTYPE html>
<html><head>
<meta http-equiv="refresh" content="0;url=?lang=$ctx->{lang}">
</head><body>Redirecting...</body></html>
};

        return _print_html_response(
            body         => $html,
            cookie_lines => [grep { defined $_ && length $_ } ($cookie_line, $session_cookie)],
        );
    }

    my $vars = {
        page_title      => lang::t($ctx, 'login_title'),
        login_title     => lang::t($ctx, 'login_title'),
        login_desc      => lang::t($ctx, 'login_desc'),
        login_button    => lang::t($ctx, 'login_button'),
        username_label  => lang::t($ctx, 'username_label'),
        password_label  => lang::t($ctx, 'password_label'),
        lang_ja_url     => _build_lang_url($ctx, 'ja'),
        lang_en_url     => _build_lang_url($ctx, 'en'),
        message         => _html_escape(lang::t($ctx, 'login_failed')),
    };

    my $html = render::render_template('template/admin/login.html', $vars);
    return _print_html_response(
        body        => $html,
        cookie_line => $cookie_line,
    );
}

sub _logout {
    my ($ctx, $cookie_line) = @_;

    my $logout_cookie = 'Set-Cookie: mark6_session=; Path=/; Max-Age=0; SameSite=Lax';
    return _redirect('?lang=' . $ctx->{lang}, [grep { defined $_ && length $_ } ($cookie_line, $logout_cookie)]);
}

sub _is_logged_in {
    my ($ctx) = @_;
    my $env = $ctx->{env} || \%ENV;
    my $cookies = _parse_cookies($env->{HTTP_COOKIE});
    return (($cookies->{mark6_session} // '') eq 'dummy_session_ok') ? 1 : 0;
}

sub _build_lang_cookie_header {
    my ($lang) = @_;
    return '' unless defined $lang && $lang =~ /^(ja|en)$/;
    return "Set-Cookie: mark6_lang=$lang; Path=/; Max-Age=31536000; SameSite=Lax";
}

sub _build_session_cookie_header {
    my ($value) = @_;
    return "Set-Cookie: mark6_session=$value; Path=/; Max-Age=86400; SameSite=Lax";
}

sub _build_lang_url {
    my ($ctx, $lang) = @_;
    my %params = %{ $ctx->{params} || {} };
    $params{lang} = $lang;

    my @pairs;
    for my $k (sort keys %params) {
        my $v = defined $params{$k} ? $params{$k} : '';
        push @pairs, _url_encode($k) . '=' . _url_encode($v);
    }

    return '?' . join('&', @pairs);
}

sub _is_allowed_lang {
    my ($lang, $dict) = @_;
    return 0 unless defined $lang && length $lang;
    return exists $dict->{$lang};
}

sub _parse_query_string {
    my ($qs) = @_;
    my %params;

    return \%params unless defined $qs && length $qs;

    for my $pair (split /&/, $qs) {
        next unless length $pair;
        my ($k, $v) = split /=/, $pair, 2;
        $k = _url_decode($k // '');
        $v = _url_decode($v // '');
        $params{$k} = $v;
    }

    return \%params;
}

sub _parse_post_body {
    my ($ctx) = @_;

    my $env = $ctx->{env} || \%ENV;
    my $method = $env->{REQUEST_METHOD} || '';
    return {} unless uc($method) eq 'POST';

    my $len = $env->{CONTENT_LENGTH} || 0;
    my $body = '';
    read(STDIN, $body, $len) if $len > 0;

    return _parse_query_string($body);
}

sub _parse_cookies {
    my ($cookie_header) = @_;
    my %cookies;

    return \%cookies unless defined $cookie_header && length $cookie_header;

    for my $pair (split /\s*;\s*/, $cookie_header) {
        my ($k, $v) = split /=/, $pair, 2;
        next unless defined $k && length $k;
        $v = '' unless defined $v;
        $cookies{$k} = $v;
    }

    return \%cookies;
}

sub _load_jsonl {
    my ($file) = @_;
    my @rows;

    return \@rows unless -e $file;

    open my $fh, '<:encoding(UTF-8)', $file
        or die "router.pm: cannot open $file: $!";

    while (my $line = <$fh>) {
        chomp $line;
        next unless $line =~ /\S/;
        my $row = eval { decode_json($line) };
        next unless $row && ref $row eq 'HASH';
        push @rows, $row;
    }

    close $fh;
    return \@rows;
}

sub _save_jsonl {
    my ($file, $rows) = @_;

    open my $fh, '>:encoding(UTF-8)', $file
        or die "router.pm: cannot write $file: $!";

    for my $row (@$rows) {
        print $fh encode_json($row) . "\n";
    }

    close $fh;
}

sub _next_article_id {
    my ($rows) = @_;
    my $max = 0;

    for my $row (@$rows) {
        my $id = $row->{id} || 0;
        $max = $id if $id =~ /^\d+$/ && $id > $max;
    }

    return $max + 1;
}

sub _redirect {
    my ($location, $cookie_input) = @_;

    my @cookie_lines;
    if (ref $cookie_input eq 'ARRAY') {
        @cookie_lines = @$cookie_input;
    } elsif (defined $cookie_input && length $cookie_input) {
        @cookie_lines = ($cookie_input);
    }

    print "Status: 302 Found\r\n";
    print "$_\r\n" for @cookie_lines;
    print "Location: $location\r\n";
    print "Content-Type: text/html; charset=UTF-8\r\n";
    print "\r\n";
    print qq{<!DOCTYPE html><html><body>Redirecting...</body></html>};
    return;
}

sub _print_html_response {
    my (%args) = @_;

    my $body = $args{body} // '';
    my @cookie_lines;

    if (ref $args{cookie_lines} eq 'ARRAY') {
        @cookie_lines = @{ $args{cookie_lines} };
    } elsif (defined $args{cookie_line} && length $args{cookie_line}) {
        @cookie_lines = ($args{cookie_line});
    }

    print "Content-Type: text/html; charset=UTF-8\r\n";
    print "$_\r\n" for @cookie_lines;
    print "\r\n";
    print $body;
    return;
}

sub _is_post {
    my ($ctx) = @_;
    my $env = $ctx->{env} || \%ENV;
    return uc($env->{REQUEST_METHOD} || '') eq 'POST';
}

sub _url_decode {
    my ($s) = @_;
    return '' unless defined $s;
    $s =~ tr/+/ /;
    $s =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
    return $s;
}

sub _url_encode {
    my ($s) = @_;
    $s = '' unless defined $s;
    $s =~ s/([^A-Za-z0-9\-\_\.\~])/sprintf("%%%02X", ord($1))/eg;
    return $s;
}

sub _html_escape {
    my ($s) = @_;
    $s = '' unless defined $s;
    $s =~ s/&/&amp;/g;
    $s =~ s/</&lt;/g;
    $s =~ s/>/&gt;/g;
    $s =~ s/"/&quot;/g;
    return $s;
}

1;
