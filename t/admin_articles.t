use strict;
use warnings;
use utf8;
use Test::More;
use File::Path qw(make_path remove_tree);
use File::Spec;
use JSON::PP ();
use Encode qw(decode encode);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);

my $perl = $^X;
my $root = File::Spec->catdir('t', 'tmp_admin_articles');

remove_tree($root) if -d $root;
make_path(File::Spec->catdir($root, 'dat', 'articles'));
make_path(File::Spec->catdir($root, 'dat', 'sessions'));
write_json(File::Spec->catfile($root, 'dat', 'users.json'), { version => 1, users => [] });
write_json(File::Spec->catfile($root, 'dat', 'config.json'), {
    version => 1,
    site => { title => 'MARK6 Test', language => 'ja', default_lang => 'ja', langs => ['ja', 'en'], node => 'oita360', base_url => '/test/mark6' },
    features => { ai => JSON::PP::true },
    ai => { provider => 'openai', model => 'test-model', api_key_env => 'MARK6_OPENAI_API_KEY' },
});
write_json(File::Spec->catfile($root, 'dat', 'home.json'), {
    title => 'Home',
    body => '',
    show_articles => JSON::PP::true,
});

my $create = `$perl tools/create_user.pl --root "$root" --name admin --password secret --rank master`;
is($? >> 8, 0, 'create_user exits ok');

my $login = run_cgi(
    script => File::Spec->catfile('admin', 'login.cgi'),
    method => 'POST',
    body   => form_data(name => 'admin', password => 'secret'),
);
my ($session_id) = $login =~ /mark6_session=([0-9a-f]{64})/;
ok($session_id, 'login sets session');

my $new_form = run_cgi(
    script => File::Spec->catfile('admin', 'articles.cgi'),
    method => 'GET',
    query  => 'command=new',
    cookie => "mark6_session=$session_id",
);
like($new_form, qr/新規記事/, 'new article form renders');
like($new_form, qr/name="title_ja"/, 'form renders Japanese title field');
like($new_form, qr/name="title_en"/, 'form renders English title field');
like($new_form, qr/value="ai_draft"/, 'form renders AI body draft action');
like($new_form, qr/value="ai_translate"/, 'form renders AI translation action');
like($new_form, qr/value="ai_rewrite"/, 'form renders AI rewrite action');
like($new_form, qr/value="ai_seo"/, 'form renders AI SEO diagnosis action');
like($new_form, qr/id="ai-assist"/, 'form provides an AI action return anchor');
my ($csrf) = $new_form =~ /name="csrf_token" value="([0-9a-f]+)"/;
ok($csrf, 'form includes csrf token');

my $save = run_cgi(
    script => File::Spec->catfile('admin', 'articles.cgi'),
    method => 'POST',
    cookie => "mark6_session=$session_id",
    body   => form_data(
        command    => 'save',
        id         => 'test-article',
        csrf_token => $csrf,
        default_lang => 'ja',
        node       => 'oita360',
        slug       => 'beppu-station',
        title_ja   => 'テスト記事',
        title_en   => 'Test article',
        status     => 'published',
        tags       => 'News, Perl',
        image      => '',
        description_ja => '<p>紹介文</p>',
        body_ja    => '<p>本文</p>',
        description_en => '<p>Summary</p>',
        body_en    => '<p>Body</p>',
    ),
);
like($save, qr/Location: articles\.cgi/, 'save redirects to article list');

my $list = run_cgi(
    script => File::Spec->catfile('admin', 'articles.cgi'),
    method => 'GET',
    cookie => "mark6_session=$session_id",
);
like($list, qr/テスト記事/, 'saved article appears in admin list');
like($list, qr/href="\/test\/mark6\/ja\/oita360\/beppu-station\/" target="_blank" rel="noopener"/, 'view link opens public article in new tab');
like($list, qr/onsubmit="return confirm\('この記事を削除しますか？'\);"/, 'delete confirms before submit');

my $saved_article = read_json(File::Spec->catfile($root, 'dat', 'articles', 'test-article.json'));
is($saved_article->{default_lang}, 'ja', 'default language saved');
is($saved_article->{node}, 'oita360', 'node saved');
is($saved_article->{slug}, 'beppu-station', 'slug saved');
is($saved_article->{langs}{ja}{title}, 'テスト記事', 'Japanese title saved');
is($saved_article->{langs}{en}{title}, 'Test article', 'English title saved');
is($saved_article->{title}, 'テスト記事', 'legacy title mirrors default language');

{
    local $ENV{MARK6_AI_MOCK_RESPONSE} = JSON::PP->new->utf8->encode({
        summary => 'AI summary',
        seo_description => 'AI SEO description',
        suggested_tags => ['Beppu', 'Station', 'Travel'],
    });
    my $ai = run_cgi(
        script => File::Spec->catfile('admin', 'articles.cgi'),
        method => 'POST',
        cookie => "mark6_session=$session_id",
        body   => form_data(
            command    => 'ai_suggest',
            id         => 'test-article',
            csrf_token => $csrf,
            default_lang => 'ja',
            node       => 'oita360',
            slug       => 'beppu-station',
            title_ja   => $saved_article->{langs}{ja}{title},
            title_en   => 'Test article',
            status     => 'published',
            tags       => 'News, Perl',
            image      => '',
            description_ja => $saved_article->{langs}{ja}{description},
            body_ja    => $saved_article->{langs}{ja}{body},
            description_en => '<p>Summary</p>',
            body_en    => '<p>Body</p>',
        ),
    );
like($ai, qr/Location: articles\.cgi\?command=edit&id=test-article&ai=done\#ai-assist/, 'AI suggestion returns to the AI action panel');
}

my $ai_article = read_json(File::Spec->catfile($root, 'dat', 'articles', 'test-article.json'));
is($ai_article->{ai}{summary}, 'AI summary', 'AI summary saved');
is($ai_article->{ai}{seo_description}, 'AI SEO description', 'AI SEO description saved');
is_deeply($ai_article->{ai}{suggested_tags}, ['Beppu', 'Station', 'Travel'], 'AI suggested tags saved');
is($ai_article->{ai}{model}, 'test-model', 'AI model saved');
like($ai_article->{ai}{last_processed_at}, qr/\A\d{4}-\d{2}-\d{2}T/, 'AI timestamp saved');

$ai_article->{ai}{seo} = {
    suggested_tags => ['Perl', 'Travel', 'travel', 'Beppu'],
};
write_json(File::Spec->catfile($root, 'dat', 'articles', 'test-article.json'), $ai_article);

my $tag_apply = run_cgi(
    script => File::Spec->catfile('admin', 'articles.cgi'),
    method => 'POST',
    cookie => "mark6_session=$session_id",
    body   => form_data(
        command    => 'ai_apply_tags',
        id         => 'test-article',
        csrf_token => $csrf,
        default_lang => 'ja',
        node       => 'oita360',
        slug       => 'beppu-station',
        title_ja   => $saved_article->{langs}{ja}{title},
        title_en   => 'Test article',
        status     => 'published',
        tags       => 'News, Perl',
        image      => '',
        description_ja => $saved_article->{langs}{ja}{description},
        body_ja    => $saved_article->{langs}{ja}{body},
        description_en => '<p>Summary</p>',
        body_en    => '<p>Body</p>',
    ),
);
like($tag_apply, qr/Location: articles\.cgi\?command=edit&id=test-article&ai=tags_applied\#ai-assist/, 'tag action returns to the AI action panel');
my $tag_article = read_json(File::Spec->catfile($root, 'dat', 'articles', 'test-article.json'));
is_deeply($tag_article->{tags}, ['News', 'Perl', 'Travel', 'Beppu'], 'tag action preserves existing tags and adds unique AI suggestions');

my $public = run_cgi(
    script => File::Spec->catfile('public', 'index.cgi'),
    method => 'GET',
    query  => 'order=focus&tar=test-article',
);
like($public, qr/テスト記事/, 'saved article appears publicly');
like($public, qr/本文/, 'public detail renders body');

my $public_en = run_cgi(
    script => File::Spec->catfile('public', 'index.cgi'),
    method => 'GET',
    path_info => '/en/oita360/beppu-station/',
);
like($public_en, qr/Test article/, 'pretty URL renders English article');
like($public_en, qr/<p>Body<\/p>/, 'pretty URL renders English body');

my $delete = run_cgi(
    script => File::Spec->catfile('admin', 'articles.cgi'),
    method => 'POST',
    cookie => "mark6_session=$session_id",
    body   => form_data(
        command    => 'delete',
        id         => 'test-article',
        csrf_token => $csrf,
    ),
);
like($delete, qr/Location: articles\.cgi/, 'delete redirects to article list');
ok(!-e File::Spec->catfile($root, 'dat', 'articles', 'test-article.json'), 'delete removes article JSON');

my $after_delete = run_cgi(
    script => File::Spec->catfile('public', 'index.cgi'),
    method => 'GET',
    query  => 'order=focus&tar=test-article',
);
like($after_delete, qr/Article not found/, 'deleted article is hidden publicly');

remove_tree($root);
done_testing;

sub run_cgi {
    my (%args) = @_;
    local $ENV{MARK6_ROOT} = $root;
    local $ENV{REQUEST_METHOD} = $args{method} || 'GET';
    local $ENV{QUERY_STRING} = $args{query} || '';
    local $ENV{PATH_INFO} = $args{path_info} || '';
    local $ENV{HTTP_COOKIE} = $args{cookie} || '';
    local $ENV{HTTPS} = '';

    my $body = $args{body} || '';
    local $ENV{CONTENT_LENGTH} = length($body);

    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, $perl, $args{script});
    print {$in} $body if $body ne '';
    close $in;
    my $output = do { local $/; <$out> };
    my $error = do { local $/; <$err> };
    waitpid($pid, 0);
    die $error if ($? >> 8) != 0;

    return decode('UTF-8', $output || '');
}

sub form_data {
    my (%pairs) = @_;
    return join '&', map { url_encode($_) . '=' . url_encode($pairs{$_}) } sort keys %pairs;
}

sub url_encode {
    my ($value) = @_;
    $value = encode('UTF-8', $value || '');
    $value =~ s/([^A-Za-z0-9_.~-])/sprintf('%%%02X', ord($1))/eg;
    return $value;
}

sub write_json {
    my ($path, $data) = @_;
    open my $fh, '>:raw', $path or die "Cannot write $path: $!";
    print {$fh} JSON::PP->new->utf8->canonical->pretty->encode($data);
    close $fh;
}

sub read_json {
    my ($path) = @_;
    open my $fh, '<:raw', $path or die "Cannot read $path: $!";
    local $/;
    my $body = <$fh>;
    close $fh;
    return JSON::PP->new->utf8->decode($body);
}
