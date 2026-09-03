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
like($new_form, qr/class="lang-tab active" type="button" data-lang-tab="lang-panel-ja"/, 'form renders language tabs');
like($new_form, qr/name="title_ja"/, 'form renders Japanese title field');
like($new_form, qr/name="title_en"/, 'form renders English title field');
like($new_form, qr/name="ai_run_draft" type="checkbox" value="1"/, 'form renders AI body draft toggle');
like($new_form, qr/name="ai_run_translate" type="checkbox" value="1"/, 'form renders AI translation toggle');
like($new_form, qr/name="ai_run_rewrite" type="checkbox" value="1"/, 'form renders AI rewrite toggle');
like($new_form, qr/name="ai_run_seo" type="checkbox" value="1"/, 'form renders AI SEO diagnosis toggle');
like($new_form, qr/name="command" value="ai_run_selected"/, 'form renders selected AI action submit');
like($new_form, qr/id="ai-assist"/, 'form provides an AI action return anchor');
like($new_form, qr/id="article-editor"/, 'form provides an article editor return anchor');
like($new_form, qr/name="kiosk_enabled"/, 'form renders Kiosk toggle');
like($new_form, qr/name="kiosk_label_1"/, 'form renders Kiosk label field');
like($new_form, qr/name="kiosk_keyword_1"/, 'form renders Kiosk keyword field');
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
        image_manual => 'https://img.youtube.com/vi/Jce1N0hRfJc/hqdefault.jpg',
        description_ja => '<p>紹介文</p>',
        body_ja    => '<p>本文</p>',
        description_en => '<p>Summary</p>',
        body_en    => '<p>Body</p>',
        kiosk_enabled => 1,
        kiosk_label_1 => 'Guide Book',
        kiosk_keyword_1 => 'travel guide',
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
like($list, qr/name="order_action" value="top"/, 'article list renders move-to-top action');
like($list, qr/name="order_position" type="number"/, 'article list renders direct order position field');
like($list, qr/onsubmit="return confirm\('この記事を削除しますか？'\);"/, 'delete confirms before submit');

my $saved_article = read_json(File::Spec->catfile($root, 'dat', 'articles', 'test-article.json'));
is($saved_article->{default_lang}, 'ja', 'default language saved');
is($saved_article->{node}, 'oita360', 'node saved');
is($saved_article->{slug}, 'beppu-station', 'slug saved');
is($saved_article->{image}, 'https://img.youtube.com/vi/Jce1N0hRfJc/hqdefault.jpg', 'external HTTPS image URL saved');
is($saved_article->{translation_status}{en}{state}, 'translated', 'newly saved English content is marked translated');
is($saved_article->{langs}{ja}{title}, 'テスト記事', 'Japanese title saved');
is($saved_article->{langs}{en}{title}, 'Test article', 'English title saved');
is($saved_article->{title}, 'テスト記事', 'legacy title mirrors default language');
ok($saved_article->{kiosk}{enabled}, 'Kiosk enabled flag saved');
is($saved_article->{kiosk}{items}[0]{label}, 'Guide Book', 'Kiosk item label saved');
is($saved_article->{kiosk}{items}[0]{keyword}, 'travel guide', 'Kiosk item keyword saved');

my $second_save = run_cgi(
    script => File::Spec->catfile('admin', 'articles.cgi'),
    method => 'POST',
    cookie => "mark6_session=$session_id",
    body   => form_data(
        command    => 'save',
        id         => 'second-article',
        csrf_token => $csrf,
        default_lang => 'ja',
        node       => 'oita360',
        slug       => 'second-post',
        title_ja   => '2番目の記事',
        title_en   => 'Second article',
        status     => 'published',
        tags       => 'News',
        image      => '',
        description_ja => '<p>2番目の紹介文</p>',
        body_ja    => '<p>2番目の本文</p>',
        description_en => '<p>Second summary</p>',
        body_en    => '<p>Second body</p>',
    ),
);
like($second_save, qr/Location: articles\.cgi/, 'second article save redirects to article list');

my $reorder = run_cgi(
    script => File::Spec->catfile('admin', 'articles.cgi'),
    method => 'POST',
    cookie => "mark6_session=$session_id",
    body   => form_data(
        command    => 'reorder',
        id         => 'second-article',
        csrf_token => $csrf,
        order_action => 'top',
    ),
);
like($reorder, qr/Location: articles\.cgi/, 'reorder redirects to article list');
my $reordered_first = read_json(File::Spec->catfile($root, 'dat', 'articles', 'second-article.json'));
my $reordered_second = read_json(File::Spec->catfile($root, 'dat', 'articles', 'test-article.json'));
is($reordered_first->{sort_order}, 10, 'move-to-top assigns first sort order');
is($reordered_second->{sort_order}, 20, 'move-to-top assigns following sort order');
my $reordered_list = run_cgi(
    script => File::Spec->catfile('admin', 'articles.cgi'),
    method => 'GET',
    cookie => "mark6_session=$session_id",
);
like($reordered_list, qr/2番目の記事[\s\S]+テスト記事/, 'admin list follows custom article order');

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

{
    local $ENV{MARK6_AI_MOCK_RESPONSE} = JSON::PP->new->utf8->encode({
        body => '<p>AI batch body</p>',
        seo_description => 'AI batch SEO description',
        suggested_tags => ['Batch', 'Travel'],
        diagnosis => 'Add more local context.',
    });
    my $batch = run_cgi(
        script => File::Spec->catfile('admin', 'articles.cgi'),
        method => 'POST',
        cookie => "mark6_session=$session_id",
        body   => form_data(
            command    => 'ai_run_selected',
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
            ai_run_draft => 1,
            ai_run_seo => 1,
        ),
    );
    like($batch, qr/Location: articles\.cgi\?command=edit&id=test-article&ai=selected_done\#ai-assist/, 'selected AI actions return to the AI action panel');
}

my $batch_article = read_json(File::Spec->catfile($root, 'dat', 'articles', 'test-article.json'));
is($batch_article->{ai}{draft}{body}, '<p>AI batch body</p>', 'selected AI action saves body draft');
is($batch_article->{ai}{seo}{seo_description}, 'AI batch SEO description', 'selected AI action saves SEO diagnosis');

my $apply_selected = run_cgi(
    script => File::Spec->catfile('admin', 'articles.cgi'),
    method => 'POST',
    cookie => "mark6_session=$session_id",
    body   => form_data(
        command    => 'ai_apply_selected',
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
        ai_apply_result => 'draft',
    ),
);
like($apply_selected, qr/Location: articles\.cgi\?command=edit&id=test-article&ai=applied\#article-editor/, 'selected AI apply returns to the article editor');
my $applied_article = read_json(File::Spec->catfile($root, 'dat', 'articles', 'test-article.json'));
is($applied_article->{langs}{ja}{body}, '<p>AI batch body</p>', 'selected AI apply updates the default language body');

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
like($tag_apply, qr/Location: articles\.cgi\?command=edit&id=test-article&ai=tags_applied\#article-editor/, 'tag action returns to the article editor');
my $tag_article = read_json(File::Spec->catfile($root, 'dat', 'articles', 'test-article.json'));
is_deeply($tag_article->{tags}, ['News', 'Perl', 'Travel', 'Beppu'], 'tag action preserves existing tags and adds unique AI suggestions');
$tag_article->{image} = 'https://img.youtube.com/vi/Jce1N0hRfJc/hqdefault.jpg';
write_json(File::Spec->catfile($root, 'dat', 'articles', 'test-article.json'), $tag_article);

my $public = run_cgi(
    script => File::Spec->catfile('public', 'index.cgi'),
    method => 'GET',
    query  => 'order=focus&tar=test-article',
);
like($public, qr/テスト記事/, 'saved article appears publicly');
like($public, qr/本文/, 'public detail renders body');

like($public, qr/<span class="kiosk-label">Guide Book<\/span>/, 'public detail renders saved Kiosk link');
like($public, qr/<span class="kiosk-keyword">検索: travel guide<\/span>/, 'public detail renders Kiosk keyword note');
like($public, qr{https://www\.amazon\.co\.jp/s\?k=travel%20guide}, 'public detail renders encoded Kiosk search URL');
like($public, qr{src="https://img\.youtube\.com/vi/Jce1N0hRfJc/hqdefault\.jpg"}, 'public detail renders external image URL');
like($public, qr{<meta property="og:image" content="https://img\.youtube\.com/vi/Jce1N0hRfJc/hqdefault\.jpg">}, 'public detail uses external image URL for Open Graph');

my $public_en = run_cgi(
    script => File::Spec->catfile('public', 'index.cgi'),
    method => 'GET',
    path_info => '/en/oita360/beppu-station/',
);
like($public_en, qr/Test article/, 'pretty URL renders English article');
like($public_en, qr/<p>Body<\/p>/, 'pretty URL renders English body');

my $source_update = run_cgi(
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
        title_ja   => $saved_article->{langs}{ja}{title},
        title_en   => 'Test article',
        status     => 'published',
        tags       => 'News, Perl, Travel, Beppu',
        image      => '',
        description_ja => $saved_article->{langs}{ja}{description},
        body_ja    => '<p>Updated source body</p>',
        description_en => '<p>Summary</p>',
        body_en    => '<p>Body</p>',
    ),
);
like($source_update, qr/Location: articles\.cgi/, 'source update redirects to article list');
my $outdated_article = read_json(File::Spec->catfile($root, 'dat', 'articles', 'test-article.json'));
is($outdated_article->{translation_status}{en}{state}, 'outdated', 'source update marks English translation outdated');

my $translation_update = run_cgi(
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
        title_ja   => $saved_article->{langs}{ja}{title},
        title_en   => 'Updated test article',
        status     => 'published',
        tags       => 'News, Perl, Travel, Beppu',
        image      => '',
        description_ja => $saved_article->{langs}{ja}{description},
        body_ja    => '<p>Updated source body</p>',
        description_en => '<p>Updated summary</p>',
        body_en    => '<p>Updated English body</p>',
    ),
);
like($translation_update, qr/Location: articles\.cgi/, 'translation update redirects to article list');
my $translated_article = read_json(File::Spec->catfile($root, 'dat', 'articles', 'test-article.json'));
is($translated_article->{translation_status}{en}{state}, 'translated', 'updating English content marks it translated');

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
