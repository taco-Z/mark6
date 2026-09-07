use strict;
use warnings;
use Test::More;
use lib 'lib';

use Mark6::Kiosk qw(config_for_lang item_type valid_url);

my $legacy = {
    enabled => 1,
    items => [{ label => 'Guide', keyword => 'travel guide' }],
};

is(config_for_lang($legacy, 'ja'), $legacy, 'legacy flat Kiosk belongs to Japanese');
is_deeply(config_for_lang($legacy, 'en'), {}, 'legacy flat Kiosk does not fall back to English');

my $localized = {
    ja => { enabled => 1, items => [] },
    en => { enabled => 1, items => [{ type => 'url', url => 'https://example.com/' }] },
};

is(config_for_lang($localized, 'en'), $localized->{en}, 'localized Kiosk returns requested language');
is_deeply(config_for_lang($localized, 'fr'), {}, 'localized Kiosk has no language fallback');
is(item_type({ keyword => 'guide' }), 'amazon', 'legacy keyword item is Amazon');
is(item_type({ type => 'amazon' }), 'amazon', 'explicit Amazon item is recognized');
is(item_type({ type => 'url' }), 'url', 'explicit URL item is recognized');
ok(valid_url('https://example.com/path?q=1'), 'HTTPS URL is accepted');
ok(valid_url('http://example.com/'), 'HTTP URL is accepted');
ok(!valid_url('javascript:alert(1)'), 'unsafe URL scheme is rejected');
ok(!valid_url('https://example.com/bad path'), 'URL containing whitespace is rejected');

done_testing;
