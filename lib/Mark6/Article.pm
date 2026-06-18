package Mark6::Article;

use strict;
use warnings;

my @DEFAULT_LANGS = qw(ja en);

sub supported_langs {
    my ($config) = @_;
    my $langs = $config->{site}{langs};
    return @{$langs} if ref($langs) eq 'ARRAY' && @{$langs};
    return @DEFAULT_LANGS;
}

sub default_lang {
    my ($article, $config) = @_;
    return $article->{default_lang} || $config->{site}{default_lang} || $config->{site}{language} || 'ja';
}

sub normalize {
    my ($article, $config) = @_;
    $article ||= {};
    my @langs = supported_langs($config || {});
    my $default = default_lang($article, $config || {});
    my %langs = ref($article->{langs}) eq 'HASH' ? %{$article->{langs}} : ();

    if (!%langs) {
        $langs{$default} = {
            title       => $article->{title} || '',
            description => $article->{intro} || $article->{description} || '',
            body        => $article->{body} || '',
        };
    }

    for my $lang (@langs) {
        $langs{$lang} ||= { title => '', description => '', body => '' };
        for my $field (qw(title description body)) {
            $langs{$lang}{$field} = '' unless defined $langs{$lang}{$field};
        }
    }

    $article->{default_lang} = $default;
    $article->{langs} = \%langs;
    return $article;
}

sub localized {
    my ($article, $lang, $config) = @_;
    $article = normalize($article, $config || {});
    my $default = default_lang($article, $config || {});
    my $entry = $article->{langs}{$lang} || {};
    my $fallback = $article->{langs}{$default} || {};

    return {
        title       => _first_text($entry->{title}, $fallback->{title}, $article->{title}, 'Untitled'),
        description => _first_text($entry->{description}, $fallback->{description}, $article->{intro}, ''),
        body        => _first_text($entry->{body}, $fallback->{body}, $article->{body}, ''),
    };
}

sub title_for {
    my ($article, $lang, $config) = @_;
    return localized($article, $lang, $config)->{title};
}

sub description_for {
    my ($article, $lang, $config) = @_;
    return localized($article, $lang, $config)->{description};
}

sub body_for {
    my ($article, $lang, $config) = @_;
    return localized($article, $lang, $config)->{body};
}

sub node_for {
    my ($article, $config) = @_;
    $article ||= {};
    return _safe_segment($article->{node} || $config->{site}{node} || 'oita360');
}

sub slug_for {
    my ($article) = @_;
    $article ||= {};
    return _safe_segment($article->{slug} || $article->{id} || '');
}

sub public_path {
    my ($article, $lang, $config) = @_;
    my $node = node_for($article, $config || {});
    my $slug = slug_for($article);
    return "/$lang/$node/$slug/";
}

sub _first_text {
    for my $value (@_) {
        return $value if defined $value && $value ne '';
    }
    return '';
}

sub _safe_segment {
    my ($value) = @_;
    $value = '' unless defined $value;
    $value =~ s/^\s+|\s+$//g;
    $value =~ s/[^0-9A-Za-z_-]+/-/g;
    $value =~ s/-+/-/g;
    $value =~ s/^-|-$//g;
    return $value;
}

1;
