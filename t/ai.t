use strict;
use warnings;
use Test::More;

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

done_testing;
