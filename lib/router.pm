package router;
use strict;
use warnings;
use utf8;

use lang;
use auth;
use article;
use render;

sub dispatch_admin {
    my ($ctx) = @_;
    my $action = $ctx->{params}->{action} || '';

    if ($action eq 'do_login') {
        return _do_login($ctx);
    }

    if ($action eq 'logout') {
        return _logout($ctx);
    }

    my $user = auth::current_user($ctx);
    unless ($user) {
        return {
            body => render::render($ctx, 'admin/login.html', {
                error        => '',
                login_title  => lang::t($ctx, 'login_title'),
                user_id      => lang::t($ctx, 'user_id'),
                password     => lang::t($ctx, 'password'),
                login_button => lang::t($ctx, 'login_button'),
            }),
        };
    }

    if ($action eq 'article_list') {
        return _article_list($ctx, $user);
    }

    if ($action eq 'article_edit') {
        return _article_edit($ctx, $user);
    }

    if ($action eq 'article_save') {
        return _article_save($ctx, $user);
    }

    if ($action eq 'article_del') {
        return _article_del($ctx, $user);
    }

    return {
        body => render::render($ctx, 'admin/dashboard.html', {
            user_name => render::h($user->{name} || $user->{id}),
            dashboard => lang::t($ctx, 'dashboard'),
        }),
    };
}

sub _do_login {
    my ($ctx) = @_;
    my $id  = $ctx->{params}->{id}  || '';
    my $pwd = $ctx->{params}->{pwd} || '';

    my $res = auth::login($ctx, $id, $pwd);

    if ($res->{ok}) {
        return {
            cookie => $res->{cookie},
            body   => render::render($ctx, 'admin/dashboard.html', {
                user_name => render::h($res->{user}->{name} || $res->{user}->{id}),
                dashboard => lang::t($ctx, 'dashboard'),
            }),
        };
    }

    return {
        body => render::render($ctx, 'admin/login.html', {
            error        => '<p style="color:red;">' . render::h(lang::t($ctx, 'login_failed')) . '</p>',
            login_title  => lang::t($ctx, 'login_title'),
            user_id      => lang::t($ctx, 'user_id'),
            password     => lang::t($ctx, 'password'),
            login_button => lang::t($ctx, 'login_button'),
        }),
    };
}

sub _logout {
    my ($ctx) = @_;

    return {
        cookie => auth::logout($ctx),
        body   => render::render($ctx, 'admin/login.html', {
            error        => '<p>' . render::h(lang::t($ctx, 'logout_done')) . '</p>',
            login_title  => lang::t($ctx, 'login_title'),
            user_id      => lang::t($ctx, 'user_id'),
            password     => lang::t($ctx, 'password'),
            login_button => lang::t($ctx, 'login_button'),
        }),
    };
}

sub _article_list {
    my ($ctx, $user) = @_;
    my $rows = article::list_articles($ctx);
    my $list_html = '';

    for my $row (@$rows) {
        my $id    = render::h($row->{id} || '');
        my $title = render::h($row->{title} || '');
        my $cat   = render::h($row->{category} || '');

        my $edit_label    = render::h(lang::t($ctx, 'article_edit'));
        my $delete_label  = render::h(lang::t($ctx, 'article_delete'));
        my $confirm_label = render::h(lang::t($ctx, 'confirm_delete'));

        $list_html .= qq{
<tr>
<td>$id</td>
<td>$title</td>
<td>$cat</td>
<td>
<a href="operation.cgi?action=article_edit&id=$id">$edit_label</a>
<a href="operation.cgi?action=article_del&id=$id" onclick="return confirm('$confirm_label')">$delete_label</a>
</td>
</tr>
};
    }

    return {
        body => render::render($ctx, 'admin/article_list.html', {
            article_rows   => $list_html,
            article_list   => lang::t($ctx, 'article_list'),
            article_edit   => lang::t($ctx, 'article_edit'),
            article_delete => lang::t($ctx, 'article_delete'),
        }),
    };
}

sub _article_edit {
    my ($ctx, $user) = @_;
    my $id  = $ctx->{params}->{id} || '';
    my $row = $id ? article::get_article($ctx, $id) : {};

    return {
        body => render::render($ctx, 'admin/article_edit.html', {
            id             => render::h($row->{id} || ''),
            title          => render::h($row->{title} || ''),
            body           => render::h($row->{body} || ''),
            category       => render::h($row->{category} || ''),
            status_1       => (($row->{status} // 1) ? 'selected' : ''),
            status_0       => (($row->{status} // 1) ? '' : 'selected'),
            article_title  => lang::t($ctx, 'article_title'),
            article_body   => lang::t($ctx, 'article_body'),
            article_category => lang::t($ctx, 'article_category'),
            article_status => lang::t($ctx, 'article_status'),
            save           => lang::t($ctx, 'save'),
        }),
    };
}

sub _article_save {
    my ($ctx, $user) = @_;

    article::save_article($ctx, {
        id       => $ctx->{params}->{id} || '',
        title    => $ctx->{params}->{title} || '',
        body     => $ctx->{params}->{body} || '',
        category => $ctx->{params}->{category} || '',
        status   => ($ctx->{params}->{status} // 1) ? 1 : 0,
    });

    return _article_list($ctx, $user);
}

sub _article_del {
    my ($ctx, $user) = @_;
    my $id = $ctx->{params}->{id} || '';

    article::delete_article($ctx, $id) if $id;

    return _article_list($ctx, $user);
}

1;
