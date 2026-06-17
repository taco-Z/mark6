package Mark6::Admin;

use strict;
use warnings;
use Mark6::CGI;

sub render_page {
    my (%args) = @_;
    my $title = $args{title} || 'Admin';
    my $content = $args{content} || '';
    my $active = $args{active} || '';
    my $safe_title = Mark6::CGI::escape_html($title);
    my $nav = admin_nav($active);

    Mark6::CGI::print_html(<<"HTML");
<!doctype html>
<html lang="ja">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$safe_title - MARK6 Admin</title>
  <link rel="stylesheet" href="../public/assets/css/mark6.css">
</head>
<body>
  <header class="site-header admin-header">
    <a class="brand" href="index.cgi">MARK6 Admin</a>
    $nav
  </header>
  <main class="site-main admin-main">$content</main>
</body>
</html>
HTML
}

sub admin_nav {
    my ($active) = @_;
    my @items = (
        [dashboard => 'Dashboard', 'index.cgi'],
        [home      => 'Home',      'home.cgi'],
        [articles  => 'Articles',  'articles.cgi'],
        [media     => 'Media',     'media.cgi'],
        [settings  => 'Settings',  'settings.cgi'],
        [view      => 'View Site', '../public/index.cgi'],
        [logout    => 'Logout',    'logout.cgi'],
    );

    my $links = join "\n", map {
        my ($key, $label, $href) = @{$_};
        my $class = $key eq $active ? ' class="active"' : '';
        qq|      <a$class href="$href">$label</a>|;
    } @items;

    return <<"HTML";
    <nav class="site-nav admin-nav">
$links
    </nav>
HTML
}

1;

