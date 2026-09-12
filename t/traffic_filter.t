use strict;
use warnings;
use Test::More;

use lib 'lib';
use Mark6::TrafficFilter;

ok((Mark6::TrafficFilter->should_count_page_view(method => 'GET', user_agent => 'Mozilla/5.0 Chrome/140 Safari/537.36'))[0], 'counts ordinary browser request');
ok(!(Mark6::TrafficFilter->should_count_page_view(method => 'GET', user_agent => 'Googlebot/2.1'))[0], 'excludes search bot');
ok(!(Mark6::TrafficFilter->should_count_page_view(method => 'GET', user_agent => 'SERankingBacklinksBot/1.0'))[0], 'excludes SEO bot');
ok(!(Mark6::TrafficFilter->should_count_page_view(method => 'GET', user_agent => 'facebookexternalhit/1.1'))[0], 'excludes social preview');
ok(!(Mark6::TrafficFilter->should_count_page_view(method => 'GET', user_agent => ''))[0], 'excludes missing user agent');
ok(!(Mark6::TrafficFilter->should_count_page_view(method => 'HEAD', user_agent => 'Mozilla/5.0'))[0], 'excludes non-GET request');

done_testing;
