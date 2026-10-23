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
like($new_form, qr/name="default_lang" value="ja"/, 'form keeps default language as a hidden value');
unlike($new_form, qr/<select name="default_lang">/, 'form does not show default language selector');
like($new_form, qr/name="title_ja"/, 'form renders Japanese title field');
like($new_form, qr/name="title_en"/, 'form renders English title field');
like($new_form, qr/data-lang-tab="ai-panel-writing"/, 'form renders AI writing tab');
like($new_form, qr/data-lang-tab="ai-panel-translate"/, 'form renders AI translation tab');
like($new_form, qr/data-lang-tab="ai-panel-seo"/, 'form renders AI SEO tab');
like($new_form, qr/data-lang-tab="ai-panel-seo-rewrite"/, 'form renders AI SEO rewrite tab');
like($new_form, qr/name="ai_run_draft" type="checkbox" value="1"/, 'form renders AI body draft toggle');
like($new_form, qr/name="ai_run_translate" type="checkbox" value="1"/, 'form renders AI translation toggle');
like($new_form, qr/name="ai_run_rewrite" type="checkbox" value="1"/, 'form renders AI rewrite toggle');
like($new_form, qr/name="ai_run_seo" type="checkbox" value="1"/, 'form renders AI SEO diagnosis toggle');
like($new_form, qr/name="ai_run_kiosk" type="checkbox" value="1"/, 'form renders AI Kiosk suggestion toggle');
like($new_form, qr/name="ai_kiosk_lang"/, 'form renders AI Kiosk target language selector');
like($new_form, qr/name="command" value="ai_run_selected"/, 'form renders selected AI action submit');
like($new_form, qr/id="ai-assist"/, 'form provides an AI action return anchor');
like($new_form, qr/id="article-editor"/, 'form provides an article editor return anchor');
like($new_form, qr/name="tags_ja"/, 'form renders Japanese tags field');
like($new_form, qr/name="tags_en"/, 'form renders English tags field');
like($new_form, qr/name="kiosk_enabled_ja"/, 'form renders Japanese Kiosk toggle');
like($new_form, qr/name="kiosk_enabled_en"/, 'form renders English Kiosk toggle');
like($new_form, qr/name="kiosk_label_ja_1"/, 'form renders localized Kiosk label field');
like($new_form, qr/name="kiosk_type_en_1"/, 'form renders localized Kiosk type field');
like($new_form, qr/name="kiosk_url_en_1"/, 'form renders English Kiosk URL field');
my ($csrf) = $new_form =~ /name="csrf_token" value="([0-9a-f]+)"/;
ok($csrf, 'form includes csrf token');

write_json(File::Spec->catfile($root, 'dat', 'articles', 'nested-tags.json'), {
    id => 'nested-tags',
    type => 'article',
    status => 'published',
    default_lang => 'ja',
    node => 'oita360',
    slug => 'nested-tags',
    langs => {
        ja => {
            title => '入れ子タグ',
            description => '<p>日本語</p>',
            body => '<p>本文</p>',
        },
        en => {
            title => 'Nested tags',
            description => '<p>English</p>',
            body => '<p>Body</p>',
            tags => ['Nested EN', 'Travel'],
        },
    },
    tags => ['日本語タグ'],
    kiosk => {
        enabled => JSON::PP::true,
        items => [{ label => 'Legacy Guide', keyword => 'legacy guide' }],
    },
    created_at => '2026-06-01T00:00:00Z',
});

my $nested_edit = run_cgi(
    script => File::Spec->catfile('admin', 'articles.cgi'),
    method => 'GET',
    query  => 'command=edit&id=nested-tags',
    cookie => "mark6_session=$session_id",
);
like($nested_edit, qr/name="tags_en" type="text" value="Nested EN, Travel"/, 'form reads tags stored inside language content');
like($nested_edit, qr/name="kiosk_label_ja_1" type="text" value="Legacy Guide"/, 'form reads legacy flat Kiosk as Japanese');
unlike($nested_edit, qr/name="kiosk_label_en_1" type="text" value="Legacy Guide"/, 'legacy flat Kiosk does not fall back to English');

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
        tags_ja    => 'ニュース, Perl',
        tags_en    => 'News, Perl',
        image      => '',
        image_manual => 'https://img.youtube.com/vi/Jce1N0hRfJc/hqdefault.jpg',
        description_ja => '<p>紹介文</p>',
        body_ja    => '<p>本文</p>',
        description_en => '<p>Summary</p>',
        body_en    => '<p>Body</p>',
        kiosk_enabled_ja => 1,
        kiosk_label_ja_1 => 'Guide Book',
        kiosk_type_ja_1 => 'amazon',
        kiosk_keyword_ja_1 => 'travel guide',
        kiosk_enabled_en => 1,
        kiosk_label_en_1 => 'Hotels near Beppu',
        kiosk_type_en_1 => 'url',
        kiosk_url_en_1 => 'https://example.com/beppu-hotels',
    ),
);
like($save, qr/Location: articles\.cgi/, 'save redirects to article list');

my $list = run_cgi(
    script => File::Spec->catfile('admin', 'articles.cgi'),
    method => 'GET',
    cookie => "mark6_session=$session_id",
);
like($list, qr/テスト記事/, 'saved article appears in admin list');
like($list, qr/class="button secondary compact" href="\/test\/mark6\/ja\/oita360\/beppu-station\/" target="_blank" rel="noopener"/, 'view link is a button and opens public article in new tab');
like($list, qr/class="button secondary compact" href="articles\.cgi\?command=edit&amp;id=test-article"/, 'edit link is rendered as a button');
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
is($saved_article->{sort_order}, 10, 'new article is assigned first sort order');
is_deeply($saved_article->{tag_langs}{ja}, ['ニュース', 'Perl'], 'Japanese localized tags saved');
is_deeply($saved_article->{tag_langs}{en}, ['News', 'Perl'], 'English localized tags saved');
ok($saved_article->{kiosk}{ja}{enabled}, 'Japanese Kiosk enabled flag saved');
is($saved_article->{kiosk}{ja}{items}[0]{label}, 'Guide Book', 'Japanese Kiosk item label saved');
is($saved_article->{kiosk}{ja}{items}[0]{type}, 'amazon', 'Japanese Kiosk item type saved');
is($saved_article->{kiosk}{ja}{items}[0]{keyword}, 'travel guide', 'Japanese Kiosk keyword saved');
ok($saved_article->{kiosk}{en}{enabled}, 'English Kiosk enabled flag saved');
is($saved_article->{kiosk}{en}{items}[0]{type}, 'url', 'English Kiosk URL type saved');
is($saved_article->{kiosk}{en}{items}[0]{url}, 'https://example.com/beppu-hotels', 'English Kiosk URL saved unchanged');

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

my $third_save = run_cgi(
    script => File::Spec->catfile('admin', 'articles.cgi'),
    method => 'POST',
    cookie => "mark6_session=$session_id",
    body   => form_data(
        command    => 'save',
        id         => 'third-article',
        csrf_token => $csrf,
        default_lang => 'ja',
        node       => 'oita360',
        slug       => 'third-post',
        title_ja   => '3番目の記事',
        title_en   => 'Third article',
        status     => 'published',
        tags       => 'News',
        description_ja => '<p>3番目の紹介文</p>',
        body_ja    => '<p>3番目の本文</p>',
    ),
);
like($third_save, qr/Location: articles\.cgi/, 'third article save redirects to article list');
my $third_article = read_json(File::Spec->catfile($root, 'dat', 'articles', 'third-article.json'));
is($third_article->{sort_order}, 0, 'new article is placed before existing ordered articles');

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
            tags_ja    => 'ニュース, Perl',
            tags_en    => 'News, Perl',
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
            tags_ja    => 'ニュース, Perl',
            tags_en    => 'News, Perl',
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

{
    local $ENV{MARK6_AI_MOCK_RESPONSE} = JSON::PP->new->utf8->encode({
        kiosk_items => [
            { label => 'Travel Guide', keyword => 'Beppu travel guide', reason => 'Matches the article topic.' },
            { label => 'Camera Gear', keyword => '360 camera accessory', reason => 'Useful for related sightseeing content.' },
        ],
    });
    my $kiosk_ai = run_cgi(
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
            tags_ja    => 'ニュース, Perl',
            tags_en    => 'News, Perl',
            image      => '',
            description_ja => $saved_article->{langs}{ja}{description},
            body_ja    => $saved_article->{langs}{ja}{body},
            description_en => '<p>Summary</p>',
            body_en    => '<p>Body</p>',
            ai_run_kiosk => 1,
            ai_kiosk_lang => 'ja',
        ),
    );
    like($kiosk_ai, qr/Location: articles\.cgi\?command=edit&id=test-article&ai=selected_done&ai_kiosk_lang=ja\#ai-assist/, 'selected AI Kiosk action returns to the AI action panel');
}

my $kiosk_ai_article = read_json(File::Spec->catfile($root, 'dat', 'articles', 'test-article.json'));
is($kiosk_ai_article->{ai}{kiosks}{ja}{items}[0]{label}, 'Travel Guide', 'Japanese AI Kiosk suggestion label saved by language');
is($kiosk_ai_article->{ai}{kiosks}{ja}{items}[0]{keyword}, 'Beppu travel guide', 'Japanese AI Kiosk suggestion keyword saved by language');
ok(!exists $kiosk_ai_article->{ai}{kiosks}{ja}{kiosk_items}, 'new AI Kiosk results use items instead of kiosk_items');

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
        tags_ja    => 'ニュース, Perl',
        tags_en    => 'News, Perl',
        image      => '',
        description_ja => $saved_article->{langs}{ja}{description},
        body_ja    => $saved_article->{langs}{ja}{body},
        description_en => '<p>Summary</p>',
        body_en    => '<p>Body</p>',
        ai_apply_draft => 1,
        ai_apply_tags => 1,
    ),
);
like($apply_selected, qr/Location: articles\.cgi\?command=edit&id=test-article&ai=applied\#article-editor/, 'selected AI apply returns to the article editor');
my $applied_article = read_json(File::Spec->catfile($root, 'dat', 'articles', 'test-article.json'));
is($applied_article->{langs}{ja}{body}, '<p>AI batch body</p>', 'selected AI apply updates the default language body');
is_deeply($applied_article->{tags}, ['ニュース', 'Perl', 'Batch', 'Travel'], 'selected AI apply can update tags at the same time');
is_deeply($applied_article->{tag_langs}{ja}, ['ニュース', 'Perl', 'Batch', 'Travel'], 'selected AI apply updates default language tags');

my $kiosk_apply = run_cgi(
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
        tags_ja    => 'ニュース, Perl',
        tags_en    => 'News, Perl',
        image      => '',
        description_ja => $saved_article->{langs}{ja}{description},
        body_ja    => $saved_article->{langs}{ja}{body},
        description_en => '<p>Summary</p>',
        body_en    => '<p>Body</p>',
        ai_apply_kiosk => 1,
    ),
);
like($kiosk_apply, qr/Location: articles\.cgi\?command=edit&id=test-article&ai=kiosk_applied\#article-editor/, 'AI Kiosk apply returns to the article editor');
my $kiosk_applied_article = read_json(File::Spec->catfile($root, 'dat', 'articles', 'test-article.json'));
is($kiosk_applied_article->{kiosk}{ja}{items}[0]{label}, 'Guide Book', 'AI Kiosk apply preserves existing localized item');
is($kiosk_applied_article->{kiosk}{ja}{items}[1]{label}, 'Travel Guide', 'AI Kiosk apply adds suggested item to its language');
is($kiosk_applied_article->{kiosk}{ja}{items}[1]{keyword}, 'Beppu travel guide', 'AI Kiosk apply adds suggested keyword');

{
    local $ENV{MARK6_AI_MOCK_RESPONSE} = JSON::PP->new->utf8->encode({
        kiosk_items => [
            { label => 'Book a Beppu tour', keyword => 'Beppu guided tours', reason => 'Useful after reading the article.' },
        ],
    });
    my $en_kiosk_ai = run_cgi(
        script => File::Spec->catfile('admin', 'articles.cgi'),
        method => 'POST',
        cookie => "mark6_session=$session_id",
        body => form_data(
            command => 'ai_run_selected',
            id => 'test-article',
            csrf_token => $csrf,
            default_lang => 'ja',
            node => 'oita360',
            slug => 'beppu-station',
            title_ja => $saved_article->{langs}{ja}{title},
            title_en => 'Test article',
            status => 'published',
            description_ja => $saved_article->{langs}{ja}{description},
            body_ja => $saved_article->{langs}{ja}{body},
            description_en => '<p>Summary</p>',
            body_en => '<p>Body</p>',
            ai_run_kiosk => 1,
            ai_kiosk_lang => 'en',
        ),
    );
    like($en_kiosk_ai, qr/ai=selected_done&ai_kiosk_lang=en\#ai-assist/, 'English AI Kiosk generation keeps selected language after redirect');
}

my $en_kiosk_ai_article = read_json(File::Spec->catfile($root, 'dat', 'articles', 'test-article.json'));
is($en_kiosk_ai_article->{ai}{kiosks}{en}{lang}, 'en', 'English AI Kiosk result is stored separately');
is($en_kiosk_ai_article->{ai}{kiosks}{ja}{items}[0]{label}, 'Travel Guide', 'English generation preserves Japanese AI Kiosk result');

my $en_kiosk_apply = run_cgi(
    script => File::Spec->catfile('admin', 'articles.cgi'),
    method => 'POST',
    cookie => "mark6_session=$session_id",
    body => form_data(
        command => 'ai_apply_selected',
        id => 'test-article',
        csrf_token => $csrf,
        default_lang => 'ja',
        node => 'oita360',
        slug => 'beppu-station',
        title_ja => $saved_article->{langs}{ja}{title},
        title_en => 'Test article',
        status => 'published',
        description_ja => $saved_article->{langs}{ja}{description},
        body_ja => $saved_article->{langs}{ja}{body},
        description_en => '<p>Summary</p>',
        body_en => '<p>Body</p>',
        ai_apply_kiosk => 1,
        ai_kiosk_lang => 'en',
    ),
);
like($en_kiosk_apply, qr/ai=kiosk_applied&ai_kiosk_lang=en\#article-editor/, 'English AI Kiosk apply keeps selected language after redirect');
my $en_kiosk_applied = read_json(File::Spec->catfile($root, 'dat', 'articles', 'test-article.json'));
is($en_kiosk_applied->{kiosk}{en}{items}[0]{url}, 'https://example.com/beppu-hotels', 'English AI apply preserves an existing administrator URL');
is($en_kiosk_applied->{kiosk}{en}{items}[1]{label}, 'Book a Beppu tour', 'English AI apply adds a service-link candidate');
is($en_kiosk_applied->{kiosk}{en}{items}[1]{url}, '', 'English AI candidate requires an administrator URL before publication');

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
        tags_ja    => 'ニュース, Perl',
        tags_en    => 'News, Perl',
        image      => '',
        description_ja => $saved_article->{langs}{ja}{description},
        body_ja    => $saved_article->{langs}{ja}{body},
        description_en => '<p>Summary</p>',
        body_en    => '<p>Body</p>',
    ),
);
like($tag_apply, qr/Location: articles\.cgi\?command=edit&id=test-article&ai=tags_applied\#article-editor/, 'tag action returns to the article editor');
my $tag_article = read_json(File::Spec->catfile($root, 'dat', 'articles', 'test-article.json'));
is_deeply($tag_article->{tags}, ['ニュース', 'Perl', 'Travel', 'Beppu'], 'tag action preserves default language tags and adds unique AI suggestions');
is_deeply($tag_article->{tag_langs}{ja}, ['ニュース', 'Perl', 'Travel', 'Beppu'], 'tag action updates default language tags');
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
like($public_en, qr/Hotels near Beppu/, 'English page renders only its localized Kiosk item');
like($public_en, qr{href="https://example\.com/beppu-hotels"}, 'English URL Kiosk uses the entered URL unchanged');
like($public_en, qr/<span class="kiosk-action">Open link<\/span>/, 'English URL Kiosk renders external link action');
unlike($public_en, qr/Guide Book/, 'English page does not fall back to Japanese Kiosk');

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

my $admin_config = read_json(File::Spec->catfile($root, 'dat', 'config.json'));
$admin_config->{site}{language} = 'en';
write_json(File::Spec->catfile($root, 'dat', 'config.json'), $admin_config);
my $english_list = run_cgi(
    script => File::Spec->catfile('admin', 'articles.cgi'),
    method => 'GET',
    cookie => "mark6_session=$session_id",
);
like($english_list, qr/>Articles<\/h1>/, 'article list switches title to English');
like($english_list, qr/Updated test article/, 'article list switches article title to English');
unlike($english_list, qr/<strong>テスト記事<\/strong>/, 'article list does not keep Japanese article title when English title exists');
like($english_list, qr/Published/, 'article list switches status label to English');
like($english_list, qr/>Edit<\/a>/, 'article list switches edit button to English');
like($english_list, qr/href="\/test\/mark6\/en\/oita360\/beppu-station\/" target="_blank" rel="noopener">View<\/a>/, 'article list view button uses admin language URL');
unlike($english_list, qr/公開/, 'article list does not keep Japanese status when admin language is English');

my $legacy_kiosk_save = run_cgi(
    script => File::Spec->catfile('admin', 'articles.cgi'),
    method => 'POST',
    cookie => "mark6_session=$session_id",
    body => form_data(
        command => 'save',
        id => 'nested-tags',
        csrf_token => $csrf,
        default_lang => 'ja',
        node => 'oita360',
        slug => 'nested-tags',
        status => 'published',
        title_ja => '入れ子タグ',
        title_en => 'Nested tags',
        tags_ja => '日本語タグ',
        tags_en => 'Nested EN, Travel',
        description_ja => '<p>日本語</p>',
        body_ja => '<p>本文</p>',
        description_en => '<p>English</p>',
        body_en => '<p>Body</p>',
        kiosk_enabled_ja => 1,
        kiosk_label_ja_1 => 'Legacy Guide',
        kiosk_type_ja_1 => 'amazon',
        kiosk_keyword_ja_1 => 'legacy guide',
        kiosk_type_en_1 => 'url',
    ),
);
like($legacy_kiosk_save, qr/Location: articles\.cgi/, 'legacy Kiosk article can be saved');
my $upgraded_legacy = read_json(File::Spec->catfile($root, 'dat', 'articles', 'nested-tags.json'));
is($upgraded_legacy->{kiosk}{ja}{items}[0]{keyword}, 'legacy guide', 'saving upgrades legacy Kiosk without losing Japanese data');
ok(!$upgraded_legacy->{kiosk}{en}{enabled}, 'saving legacy Kiosk creates disabled English configuration');

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

write_json(File::Spec->catfile($root, 'dat', 'articles', 'memory-test.json'), {
    id => 'memory-test', title => 'Private memory', node => 'sati-memory', status => 'draft',
    memory => {source => 'sati'}, visibility => 'private', review => {state => 'pending'},
});
my $approved = run_cgi(script => 'admin/articles.cgi', method => 'POST', cookie => "mark6_session=$session_id",
    body => form_data(command => 'save', csrf_token => $csrf, id => 'memory-test', status => 'published', title_ja => 'Reviewed public memory', body_ja => 'Reviewed text'));
like($approved, qr/Location: articles\.cgi/, 'master manually publishes memory');
my $reviewed = read_json(File::Spec->catfile($root, 'dat', 'articles', 'memory-test.json'));
is($reviewed->{review}{state}, 'approved', 'manual save records approval');
ok($reviewed->{review}{approved_by}, 'approval records administrator');
is($reviewed->{visibility}, 'public', 'manual save changes visibility');
my $users = read_json(File::Spec->catfile($root, 'dat', 'users.json'));
$users->{users}[0]{rank} = 'writer';
write_json(File::Spec->catfile($root, 'dat', 'users.json'), $users);
my $denied = run_cgi(script => 'admin/articles.cgi', method => 'POST', cookie => "mark6_session=$session_id",
    body => form_data(command => 'save', csrf_token => $csrf, id => 'memory-test', status => 'published', title_ja => 'Writer change'));
like($denied, qr/Only a master administrator/, 'writer cannot approve memory');
is(read_json(File::Spec->catfile($root, 'dat', 'articles', 'memory-test.json'))->{title}, 'Reviewed public memory', 'denied save preserves reviewed data');
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
