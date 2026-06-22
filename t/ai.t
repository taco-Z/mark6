use strict;
use warnings;
use Test::More;
use File::Temp qw(tempfile);

use Mark6::AI;

{
    local $ENV{MARK6_OPENAI_API_KEY} = 'direct-key';
    local $ENV{REDIRECT_MARK6_OPENAI_API_KEY} = '';
    is(Mark6::AI::_env_value('MARK6_OPENAI_API_KEY'), 'direct-key', 'reads direct environment variable');
}

{
    local $ENV{MARK6_OPENAI_API_KEY} = '';
    local $ENV{REDIRECT_MARK6_OPENAI_API_KEY} = 'redirect-key';
    is(Mark6::AI::_env_value('MARK6_OPENAI_API_KEY'), 'redirect-key', 'reads REDIRECT-prefixed environment variable');
}

{
    local $ENV{MARK6_OPENAI_API_KEY} = '';
    local $ENV{REDIRECT_MARK6_OPENAI_API_KEY} = '';
    local $ENV{REDIRECT_REDIRECT_MARK6_OPENAI_API_KEY} = 'double-redirect-key';
    is(Mark6::AI::_env_value('MARK6_OPENAI_API_KEY'), 'double-redirect-key', 'reads repeated REDIRECT-prefixed environment variable');
}

{
    my ($fh, $path) = tempfile();
    print {$fh} "file-key\n";
    close $fh;
    is(Mark6::AI::_file_value($path), 'file-key', 'reads API key from file');
}

{
    my $result = Mark6::AI::_decode_json_text('{"summary":"別府駅の紹介","seo_description":"温泉街への玄関口です。","suggested_tags":["別府","観光"]}');
    is($result->{summary}, '別府駅の紹介', 'decodes JSON text containing wide characters');
    is_deeply($result->{suggested_tags}, ['別府', '観光'], 'keeps Japanese tag strings');
}

my $article = {
    default_lang => 'ja',
    node => 'oita360',
    slug => 'beppu-station',
    langs => {
        ja => { title => 'Beppu Station', description => '<p>Gateway to Beppu.</p>', body => '<p>Source body.</p>' },
        en => { title => '', description => '', body => '' },
    },
};
my $assistant = Mark6::AI->new(config => { ai => { model => 'test-model' } });

{
    local $ENV{MARK6_AI_MOCK_RESPONSE} = '{"body":"<p>Draft body.</p>"}';
    my $result = $assistant->draft_body(article => $article, lang => 'ja');
    is($result->{body}, '<p>Draft body.</p>', 'generates a body draft result');
    is($result->{model}, 'test-model', 'records the draft model');
}

{
    local $ENV{MARK6_AI_MOCK_RESPONSE} = '{"title":"Beppu Station","description":"<p>English description.</p>","body":"<p>English body.</p>"}';
    my $result = $assistant->translate_article(article => $article, source_lang => 'ja', target_lang => 'en');
    is($result->{title}, 'Beppu Station', 'generates a translation title');
    is($result->{target_lang}, 'en', 'records the translation target language');
}

{
    local $ENV{MARK6_AI_MOCK_RESPONSE} = '{"body":"<p>Rewritten body.</p>"}';
    my $result = $assistant->rewrite_body(article => $article, lang => 'ja');
    is($result->{body}, '<p>Rewritten body.</p>', 'generates a rewritten body result');
}

{
    local $ENV{MARK6_AI_MOCK_RESPONSE} = '{"seo_description":"SEO description.","suggested_tags":["Travel","Beppu"],"diagnosis":"Add a clearer heading."}';
    my $result = $assistant->diagnose_seo(article => $article);
    is($result->{seo_description}, 'SEO description.', 'generates an SEO description');
    is($result->{diagnosis}, 'Add a clearer heading.', 'generates an SEO diagnosis');
    is_deeply($result->{suggested_tags}, ['Travel', 'Beppu'], 'generates SEO tag suggestions');
}

{
    local $ENV{MARK6_AI_MOCK_RESPONSE} = '{"body":"<h2>Improved heading</h2><p>SEO-aware body.</p>"}';
    my $result = $assistant->seo_rewrite_body(
        article => $article,
        lang    => 'ja',
        seo     => {
            seo_description => 'SEO description.',
            suggested_tags  => ['Travel', 'Beppu'],
            diagnosis       => 'Add a clearer heading.',
        },
    );
    is($result->{body}, '<h2>Improved heading</h2><p>SEO-aware body.</p>', 'generates an SEO-aware rewrite result');
}

done_testing;
