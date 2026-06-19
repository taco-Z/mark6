package Mark6::Admin;

use strict;
use warnings;
use Mark6::CGI;
use Mark6::Lang;

sub render_page {
    my (%args) = @_;
    my $title = $args{title} || 'Admin';
    my $content = $args{content} || '';
    my $active = $args{active} || '';
    my $lang = $args{lang} || Mark6::Lang->new(root => $args{root} || '.');
    my $safe_title = Mark6::CGI::escape_html($title);
    my $admin_title = Mark6::CGI::escape_html($lang->t('admin.title', 'Admin'));
    my $html_lang = Mark6::CGI::escape_html($lang->code);
    my $nav = admin_nav($active, $lang);

    Mark6::CGI::print_html(<<"HTML");
<!doctype html>
<html lang="$html_lang">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$safe_title - MARK6 $admin_title</title>
  <link rel="stylesheet" href="../public/assets/css/mark6.css">
</head>
<body>
  <header class="site-header admin-header">
    <a class="brand" href="index.cgi">MARK6 $admin_title</a>
    $nav
  </header>
  <main class="site-main admin-main">$content</main>
</body>
</html>
HTML
}

sub admin_nav {
    my ($active, $lang) = @_;
    $lang ||= Mark6::Lang->new;

    my @items = (
        [dashboard => 'admin.nav.dashboard', 'Dashboard', 'index.cgi'],
        [home      => 'admin.nav.home',      'Home',      'home.cgi'],
        [articles  => 'admin.nav.articles',  'Articles',  'articles.cgi'],
        [media     => 'admin.nav.media',     'Media',     'media.cgi'],
        [settings  => 'admin.nav.settings',  'Settings',  'settings.cgi'],
        [view      => 'admin.nav.view_site', 'View Site', '../public/index.cgi', ' target="_blank" rel="noopener"'],
        [logout    => 'admin.nav.logout',    'Logout',    'logout.cgi'],
    );

    my $links = join "\n", map {
        my ($key, $label_key, $fallback, $href, $attrs) = @{$_};
        my $label = Mark6::CGI::escape_html($lang->t($label_key, $fallback));
        my $class = $key eq $active ? ' class="active"' : '';
        $attrs ||= '';
        qq|      <a$class href="$href"$attrs>$label</a>|;
    } @items;

    return <<"HTML";
    <nav class="site-nav admin-nav">
$links
    </nav>
HTML
}

1;
