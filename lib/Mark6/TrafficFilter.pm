package Mark6::TrafficFilter;

use strict;
use warnings;

sub should_count_page_view {
    my ($class, %args) = @_;
    my $method = uc($args{method} || 'GET');
    return (0, 'method') unless $method eq 'GET';

    my $user_agent = $args{user_agent} || '';
    $user_agent =~ s/^\s+|\s+$//g;
    return (0, 'missing_user_agent') if $user_agent eq '';

    return (0, 'automated_user_agent') if $user_agent =~ m{
        (?:
            bot|crawler|spider|slurp|archiver|feedfetcher|
            curl|wget|libwww|python-requests|aiohttp|httpclient|okhttp|
            headless|lighthouse|pagespeed|
            facebookexternalhit|telegrambot|discordbot|slackbot|whatsapp|pinterestbot|
            uptimerobot|pingdom|statuscake|site24x7|healthcheck|newrelic|datadog
        )
    }ix;

    return (1, 'browser_like');
}

1;
