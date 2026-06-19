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

done_testing;
