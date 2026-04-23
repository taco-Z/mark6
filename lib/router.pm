package router;
use strict;
use warnings;
use utf8;

use JSON::PP ();
use lang ();
use render ();
use web ();

sub dispatch {
    my ($ctx) = @_;

    my $action = $ctx->{params}->{action} || '';
    my $cookie = '';
    my $method = uc($ctx->{env}->{REQUEST_METHOD} || 'GET');

    if (defined $ctx->{params}->{lang} && $ctx->{params}->{lang} =~ /^(?:ja|en)$/) {
        $cookie = web::make_cookie(
            name    => 'mark6_lang',
            value   => $ctx->{params}->{lang},
            path    => '/',
            max_age => 31536000,
        );
    }

    if ($action eq 'do_login' && $method eq 'POST') {
        return _do_login($ctx, $cookie);
    }

    if ($action eq 'logout') {
        return {
            body     => _redirect_body(),
            cookie   => web::make_cookie(
                name    => 'mark6_admin',
                value   => '',
                path    => '/',
                max_age => 0,
            ),
            location => _url($ctx, action => 'login'),
        };
    }

    if (!_is_logged_in($ctx)) {
        return _login_page($ctx, $cookie);
    }

    if ($action eq 'article_edit') {
        return _article_edit_page($ctx, $cookie);
    }

    if ($action eq 'article_save' && $method eq 'POST') {
        return _article_save($ctx, $cookie);
    }

    return _article_list_page($ctx, $cookie);
}

sub _login_page {
    my ($ctx, $cookie, $message) = @_;

    my $template = <<'HTML';
<!doctype html>
<html lang="{{lang}}">
<head>
<meta charset="UTF-8">
<title>{{site_title}} - {{login_title}}</title>
</head>
<body>
<h1>{{login_title}}</h1>
<p><a href="{{ja_url}}">JA</a> | <a href="{{en_url}}">EN</a></p>
<div>{{message}}</div>
<form method="post" action="{{login_action}}">
<p>{{user_id}}<br><input type="text" name="id"></p>
<p>{{password}}<br><input type="password" name="pwd"></p>
<p><button type="submit">{{login_button}}</button></p>
</form>
</body>
</html>
HTML

    return {
        body => render::render_template($template, {
            lang         => $ctx->{lang},
            site_title   => _text($ctx, 'site_title'),
            login_title  => _text($ctx, 'login_title'),
            login_button => _text($ctx, 'login_button'),
            user_id      => _text($ctx, 'user_id'),
            password     => _text($ctx, 'password'),
            ja_url       => _url($ctx, action => 'login', lang => 'ja'),
            en_url       => _url($ctx, action => 'login', lang => 'en'),
            login_action => _url($ctx, action => 'do_login'),
            message      => defined $message && length $message ? '<p>' . _escape_html($message) . '</p>' : '',
        }),
        cookie   => $cookie,
        location => '',
    };
}

sub _do_login {
    my ($ctx, $cookie) = @_;

    my $id  = $ctx->{params}->{id}  // '';
    my $pwd = $ctx->{params}->{pwd} // '';

    if ($id eq 'admin' && $pwd eq 'mark6') {
        return {
            body     => _redirect_body(),
            cookie   => web::make_cookie(
                name    => 'mark6_admin',
                value   => '1',
                path    => '/',
                max_age => 86400,
            ),
            location => _url($ctx, action => 'article_list'),
        };
    }

    return _login_page($ctx, $cookie, _text($ctx, 'login_failed'));
}

sub _article_list_page {
    my ($ctx, $cookie) = @_;

    my $rows = _load_articles($ctx);
    my $list = '';

    for my $row (@{$rows}) {
        my $id       = _escape_html($row->{id} // '');
        my $title    = _escape_html($row->{title} // '');
        my $category = _escape_html($row->{category} // '');
        my $status   = ($row->{status} // '') eq '1' ? _text($ctx, 'public_status') : _text($ctx, 'draft_status');

        $list .= qq{<tr><td>$id</td><td>$title</td><td>$category</td><td>} . _escape_html($status) . qq{</td><td><a href="}
              . _url($ctx, action => 'article_edit', id => $row->{id})
              . qq{">} . _escape_html(_text($ctx, 'article_edit')) . qq{</a></td></tr>\n};
    }

    if ($list eq '') {
        $list = qq{<tr><td colspan="5">} . _escape_html(_text($ctx, 'empty_articles')) . qq{</td></tr>};
    }

    my $template = <<'HTML';
<!doctype html>
<html lang="{{lang}}">
<head>
<meta charset="UTF-8">
<title>{{site_title}} - {{article_list}}</title>
</head>
<body>
<h1>{{article_list}}</h1>
<p>
<a href="{{new_url}}">{{article_new}}</a> |
<a href="{{logout_url}}">{{logout_label}}</a> |
<a href="{{ja_url}}">JA</a> |
<a href="{{en_url}}">EN</a>
</p>
<table border="1" cellpadding="6">
<tr>
<th>ID</th>
<th>{{title_label}}</th>
<th>{{category_label}}</th>
<th>{{status_label}}</th>
<th>{{article_edit}}</th>
</tr>
{{article_rows}}
</table>
</body>
</html>
HTML

    return {
        body => render::render_template($template, {
            lang           => $ctx->{lang},
            site_title     => _text($ctx, 'site_title'),
            article_list   => _text($ctx, 'article_list'),
            article_new    => _text($ctx, 'article_new'),
            logout_label   => _text($ctx, 'logout_label'),
            title_label    => _text($ctx, 'title_label'),
            category_label => _text($ctx, 'category_label'),
            status_label   => _text($ctx, 'status_label'),
            article_edit   => _text($ctx, 'article_edit'),
            article_rows   => $list,
            new_url        => _url($ctx, action => 'article_edit'),
            logout_url     => _url($ctx, action => 'logout'),
            ja_url         => _url($ctx, action => 'article_list', lang => 'ja'),
            en_url         => _url($ctx, action => 'article_list', lang => 'en'),
        }),
        cookie   => $cookie,
        location => '',
    };
}

sub _article_edit_page {
    my ($ctx, $cookie) = @_;

    my $article = _find_article($ctx, $ctx->{params}->{id});
    my $status  = defined $article->{status} ? $article->{status} : '0';

    my $template = <<'HTML';
<!doctype html>
<html lang="{{lang}}">
<head>
<meta charset="UTF-8">
<title>{{site_title}} - {{article_edit}}</title>
</head>
<body>
<h1>{{article_edit}}</h1>
<p>
<a href="{{list_url}}">{{article_list}}</a> |
<a href="{{logout_url}}">{{logout_label}}</a>
</p>
<form method="post" action="{{save_action}}">
<input type="hidden" name="id" value="{{id}}">
<p>{{title_label}}<br><input type="text" name="title" value="{{title}}" size="80"></p>
<p>{{category_label}}<br><input type="text" name="category" value="{{category}}" size="40"></p>
<p>{{status_label}}<br>
<select name="status">
<option value="1" {{status_1}}>{{public_status}}</option>
<option value="0" {{status_0}}>{{draft_status}}</option>
</select>
</p>
<p>{{body_label}}<br><textarea name="body" rows="20" cols="100">{{body}}</textarea></p>
<p><button type="submit">{{save_button}}</button></p>
</form>
</body>
</html>
HTML

    return {
        body => render::render_template($template, {
            lang           => $ctx->{lang},
            site_title     => _text($ctx, 'site_title'),
            article_edit   => _text($ctx, 'article_edit'),
            article_list   => _text($ctx, 'article_list'),
            logout_label   => _text($ctx, 'logout_label'),
            title_label    => _text($ctx, 'title_label'),
            category_label => _text($ctx, 'category_label'),
            status_label   => _text($ctx, 'status_label'),
            body_label     => _text($ctx, 'body_label'),
            save_button    => _text($ctx, 'save_button'),
            public_status  => _text($ctx, 'public_status'),
            draft_status   => _text($ctx, 'draft_status'),
            id             => _escape_html($article->{id} // ''),
            title          => _escape_html($article->{title} // ''),
            category       => _escape_html($article->{category} // ''),
            body           => _escape_html($article->{body} // ''),
            status_1       => $status eq '1' ? 'selected' : '',
            status_0       => $status eq '1' ? '' : 'selected',
            list_url       => _url($ctx, action => 'article_list'),
            logout_url     => _url($ctx, action => 'logout'),
            save_action    => _url($ctx, action => 'article_save'),
        }),
        cookie   => $cookie,
        location => '',
    };
}

sub _article_save {
    my ($ctx, $cookie) = @_;

    my $rows = _load_articles($ctx);

    my $id = defined $ctx->{params}->{id} && length $ctx->{params}->{id}
        ? $ctx->{params}->{id}
        : _next_article_id($rows);

    my $record = {
        id       => "$id",
        title    => $ctx->{params}->{title} // '',
        category => $ctx->{params}->{category} // '',
        body     => $ctx->{params}->{body} // '',
        status   => ($ctx->{params}->{status} // '0') eq '1' ? '1' : '0',
    };

    my $updated = 0;
    for my $row (@{$rows}) {
        next unless ($row->{id} // '') eq $record->{id};
        %{$row} = %{$record};
        $updated = 1;
        last;
    }

    push @{$rows}, $record unless $updated;

    _save_articles($ctx, $rows);

    return {
        body     => _redirect_body(),
        cookie   => $cookie,
        location => _url($ctx, action => 'article_list'),
    };
}

sub _is_logged_in {
    my ($ctx) = @_;
    return ($ctx->{cookies}->{mark6_admin} // '') eq '1' ? 1 : 0;
}

sub _load_articles {
    my ($ctx) = @_;
    my $path = $ctx->{base_dir} . '/dat/article.jsonl';
    my @rows;

    return \@rows unless -f $path;

    open my $fh, '<:encoding(UTF-8)', $path
        or die "Cannot open $path: $!";

    while (my $line = <$fh>) {
        chomp $line;
        next unless $line =~ /\S/;
        my $row = eval { JSON::PP::decode_json($line) };
        next unless ref $row eq 'HASH';
        push @rows, $row;
    }

    close $fh;
    return \@rows;
}

sub _save_articles {
    my ($ctx, $rows) = @_;
    my $path = $ctx->{base_dir} . '/dat/article.jsonl';

    open my $fh, '>:encoding(UTF-8)', $path
        or die "Cannot write $path: $!";

    for my $row (@{$rows}) {
        print {$fh} JSON::PP::encode_json($row) . "\n";
    }

    close $fh;
}

sub _find_article {
    my ($ctx, $id) = @_;

    return {} unless defined $id && length $id;

    my $rows = _load_articles($ctx);
    for my $row (@{$rows}) {
        return $row if ($row->{id} // '') eq $id;
    }

    return {};
}

sub _next_article_id {
    my ($rows) = @_;
    my $max = 0;

    for my $row (@{$rows}) {
        my $id = $row->{id} // 0;
        next unless $id =~ /^\d+$/;
        $max = $id if $id > $max;
    }

    return $max + 1;
}

sub _text {
    my ($ctx, $key) = @_;
    return lang::text($ctx, $key);
}

sub _url {
    my ($ctx, %extra) = @_;

    my %params = (
        action => ($ctx->{params}->{action} || 'article_list'),
        lang   => $ctx->{lang},
    );

    for my $key (keys %extra) {
        if (defined $extra{$key} && $extra{$key} ne '') {
            $params{$key} = $extra{$key};
        } else {
            delete $params{$key};
        }
    }

    my @pairs;
    for my $key (sort keys %params) {
        next unless defined $params{$key};
        push @pairs, web::url_encode($key) . '=' . web::url_encode($params{$key});
    }

    return 'operation.cgi' . (@pairs ? '?' . join('&', @pairs) : '');
}

sub _escape_html {
    my ($value) = @_;
    $value = '' unless defined $value;
    $value =~ s/&/&amp;/g;
    $value =~ s/</&lt;/g;
    $value =~ s/>/&gt;/g;
    $value =~ s/"/&quot;/g;
    $value =~ s/'/&#39;/g;
    return $value;
}

sub _redirect_body {
    return '<!doctype html><html><body>Redirecting...</body></html>';
}

1;
