package Mark6::AI;

use strict;
use warnings;
use JSON::PP qw(decode_json);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);

sub new {
    my ($class, %args) = @_;
    my $config = $args{config} || {};
    my $ai = $config->{ai} || {};

    return bless {
        provider    => $ai->{provider} || 'openai',
        model       => $ai->{model} || _env_value('MARK6_OPENAI_MODEL') || 'gpt-5.2',
        api_key_env => $ai->{api_key_env} || 'MARK6_OPENAI_API_KEY',
    }, $class;
}

sub suggest_article {
    my ($self, %args) = @_;
    my $article = $args{article} || {};
    my $mock = $ENV{MARK6_AI_MOCK_RESPONSE};
    my $result = defined $mock && $mock ne ''
        ? decode_json($mock)
        : $self->_suggest_article_openai($article);

    return _normalize_result($result, $self->{provider}, $self->{model});
}

sub _suggest_article_openai {
    my ($self, $article) = @_;
    die "Unsupported AI provider: $self->{provider}" unless $self->{provider} eq 'openai';

    my $api_key = _env_value($self->{api_key_env});
    die "AI API key is not configured. Set $self->{api_key_env}." if $api_key eq '';

    my $payload = JSON::PP->new->utf8->canonical->encode({
        model => $self->{model},
        input => [
            {
                role => 'system',
                content => join("\n",
                    'You are an editorial assistant for a lightweight CMS.',
                    'Return only one JSON object.',
                    'The JSON object must have: summary, seo_description, suggested_tags.',
                    'summary and seo_description must be concise plain text.',
                    'suggested_tags must be an array of short tag strings.',
                ),
            },
            {
                role => 'user',
                content => article_prompt($article),
            },
        ],
    });

    my ($output, $error, $exit) = _run_curl($api_key, $payload);
    die "OpenAI request failed: $error" if $exit != 0;

    my $response = decode_json($output);
    my $text = _response_text($response);
    die "OpenAI response did not include text output." if $text eq '';

    $text =~ s/\A\s*```(?:json)?\s*//;
    $text =~ s/\s*```\s*\z//;
    return decode_json($text);
}

sub article_prompt {
    my ($article) = @_;
    my @parts = (
        "Default language: " . ($article->{default_lang} || ''),
        "Node: " . ($article->{node} || ''),
        "Slug: " . ($article->{slug} || ''),
        "Tags: " . join(', ', @{$article->{tags} || []}),
    );

    my $langs = $article->{langs} || {};
    for my $code (sort keys %{$langs}) {
        my $entry = $langs->{$code} || {};
        push @parts, uc($code) . " title:\n" . ($entry->{title} || '');
        push @parts, uc($code) . " description:\n" . _strip_html($entry->{description} || '');
        push @parts, uc($code) . " body:\n" . _strip_html($entry->{body} || '');
    }

    return join("\n\n", @parts);
}

sub _run_curl {
    my ($api_key, $payload) = @_;
    my $err = gensym;
    my $pid = open3(
        my $in,
        my $out,
        $err,
        'curl',
        '-sS',
        '--fail-with-body',
        'https://api.openai.com/v1/responses',
        '-H',
        "Authorization: Bearer $api_key",
        '-H',
        'Content-Type: application/json',
        '-d',
        '@-',
    );
    print {$in} $payload;
    close $in;

    my $output = do { local $/; <$out> };
    my $error = do { local $/; <$err> };
    waitpid($pid, 0);
    return ($output || '', $error || '', $? >> 8);
}

sub _env_value {
    my ($name) = @_;
    return '' unless defined $name && $name ne '';

    my $candidate = $name;
    for (1 .. 6) {
        return $ENV{$candidate} if defined $ENV{$candidate} && $ENV{$candidate} ne '';
        $candidate = "REDIRECT_$candidate";
    }

    return '';
}

sub _response_text {
    my ($response) = @_;
    return $response->{output_text} if defined $response->{output_text};

    my @texts;
    for my $item (@{$response->{output} || []}) {
        for my $content (@{$item->{content} || []}) {
            push @texts, $content->{text} if defined $content->{text};
        }
    }
    return join "\n", @texts;
}

sub _normalize_result {
    my ($result, $provider, $model) = @_;
    my @tags = ref($result->{suggested_tags}) eq 'ARRAY' ? @{$result->{suggested_tags}} : ();
    @tags = grep { $_ ne '' } map {
        my $tag = defined $_ ? "$_" : '';
        $tag =~ s/^\s+|\s+$//g;
        $tag;
    } @tags;
    @tags = @tags[0 .. 9] if @tags > 10;

    return {
        summary           => _clean_text($result->{summary} || ''),
        seo_description   => _clean_text($result->{seo_description} || ''),
        suggested_tags    => \@tags,
        provider          => $provider,
        model             => $model,
        last_processed_at => _iso_now(),
    };
}

sub _strip_html {
    my ($value) = @_;
    $value =~ s/<[^>]+>/ /g;
    $value =~ s/&nbsp;/ /g;
    $value =~ s/&amp;/&/g;
    $value =~ s/&lt;/</g;
    $value =~ s/&gt;/>/g;
    $value =~ s/\s+/ /g;
    $value =~ s/^\s+|\s+$//g;
    return $value;
}

sub _clean_text {
    my ($value) = @_;
    $value =~ s/\r?\n/ /g;
    $value =~ s/\s+/ /g;
    $value =~ s/^\s+|\s+$//g;
    return $value;
}

sub _iso_now {
    my @t = gmtime(time);
    return sprintf('%04d-%02d-%02dT%02d:%02d:%02dZ',
        $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0]);
}

1;
