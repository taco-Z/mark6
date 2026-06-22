package Mark6::AI;

use strict;
use warnings;
use Cwd qw(abs_path);
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
        api_key_file => $ai->{api_key_file} || _env_value('MARK6_OPENAI_API_KEY_FILE') || default_api_key_file(),
    }, $class;
}

sub suggest_article {
    my ($self, %args) = @_;
    my $result = $self->_request_json(
        system => join("\n",
            'You are an editorial assistant for a lightweight CMS.',
            'Return only one JSON object.',
            'The JSON object must have: summary, seo_description, suggested_tags.',
            'summary and seo_description must be concise plain text.',
            'suggested_tags must be an array of short tag strings.',
        ),
        prompt => article_prompt($args{article} || {}),
    );
    return _normalize_result($result, $self->{provider}, $self->{model});
}

sub draft_body {
    my ($self, %args) = @_;
    my $lang = $args{lang} || 'ja';
    my $result = $self->_request_json(
        system => join("\n",
            'You write a first draft of an article body for a lightweight CMS.',
            "Write in language code: $lang.",
            'Return only one JSON object with a body property.',
            'body must be an HTML fragment using simple semantic tags such as p, h2, ul, li, strong, and a.',
            'Do not include html, head, body, markdown fences, or an explanation.',
        ),
        prompt => article_prompt($args{article} || {}),
    );
    return _normalize_body_result($result, $self->{provider}, $self->{model});
}

sub translate_article {
    my ($self, %args) = @_;
    my $source_lang = $args{source_lang} || 'ja';
    my $target_lang = $args{target_lang} || 'en';
    my $article = $args{article} || {};
    my $source = ($article->{langs} || {})->{$source_lang} || {};
    my $prompt = join("\n\n",
        "Translate this article from $source_lang to $target_lang.",
        "Title:\n" . ($source->{title} || ''),
        "Description HTML:\n" . ($source->{description} || ''),
        "Body HTML:\n" . ($source->{body} || ''),
    );
    my $result = $self->_request_json(
        system => join("\n",
            'You are a careful website translator.',
            "Translate into language code: $target_lang.",
            'Return only one JSON object with title, description, and body.',
            'title is plain text. description and body are HTML fragments.',
            'Preserve links, factual details, and the HTML structure where possible.',
            'Do not include markdown fences or an explanation.',
        ),
        prompt => $prompt,
    );
    return _normalize_translation_result($result, $self->{provider}, $self->{model}, $source_lang, $target_lang);
}

sub rewrite_body {
    my ($self, %args) = @_;
    my $lang = $args{lang} || 'ja';
    my $article = $args{article} || {};
    my $entry = ($article->{langs} || {})->{$lang} || {};
    my $prompt = join("\n\n",
        'Rewrite this existing article body for clarity, readability, and useful structure. Keep its facts and intent.',
        "Title:\n" . ($entry->{title} || ''),
        "Description HTML:\n" . ($entry->{description} || ''),
        "Body HTML:\n" . ($entry->{body} || ''),
    );
    my $result = $self->_request_json(
        system => join("\n",
            'You are a careful website editor.',
            "Write in language code: $lang.",
            'Return only one JSON object with a body property.',
            'body must be an HTML fragment. Preserve factual claims and links unless the source is clearly malformed.',
            'Do not include markdown fences or an explanation.',
        ),
        prompt => $prompt,
    );
    return _normalize_body_result($result, $self->{provider}, $self->{model});
}

sub seo_rewrite_body {
    my ($self, %args) = @_;
    my $lang = $args{lang} || 'ja';
    my $article = $args{article} || {};
    my $entry = ($article->{langs} || {})->{$lang} || {};
    my $seo = $args{seo} || {};
    my $diagnosis = $seo->{diagnosis} || '';
    my $seo_description = $seo->{seo_description} || '';
    my $tags = join(', ', @{$seo->{suggested_tags} || []});

    die 'Run an SEO diagnosis before requesting an SEO rewrite.'
        if $diagnosis eq '' && $seo_description eq '' && $tags eq '';

    my $prompt = join("\n\n",
        'Improve this existing article body using the supplied SEO review.',
        "Title:\n" . ($entry->{title} || ''),
        "Description HTML:\n" . ($entry->{description} || ''),
        "Body HTML:\n" . ($entry->{body} || ''),
        "SEO description suggestion:\n$seo_description",
        "Suggested tags:\n$tags",
        "SEO diagnosis:\n$diagnosis",
    );
    my $result = $self->_request_json(
        system => join("\n",
            'You are a careful website editor with SEO expertise.',
            "Write in language code: $lang.",
            'Return only one JSON object with a body property.',
            'body must be an HTML fragment using simple semantic tags such as p, h2, ul, li, strong, and a.',
            'Address the useful SEO review points naturally. Do not stuff keywords or invent facts.',
            'Preserve factual claims, links, and the article tone unless the source is clearly malformed.',
            'Do not include markdown fences or an explanation.',
        ),
        prompt => $prompt,
    );
    return _normalize_body_result($result, $self->{provider}, $self->{model});
}

sub diagnose_seo {
    my ($self, %args) = @_;
    my $lang = $args{lang} || ($args{article} || {})->{default_lang} || 'ja';
    my $result = $self->_request_json(
        system => join("\n",
            'You are an SEO editor for a website article.',
            "Write in language code: $lang.",
            'Return only one JSON object with seo_description, suggested_tags, and diagnosis.',
            'seo_description and diagnosis must be concise plain text.',
            'suggested_tags must be an array of short tag strings.',
            'diagnosis must mention only concrete improvements grounded in the supplied article.',
        ),
        prompt => article_prompt($args{article} || {}),
    );
    return _normalize_seo_result($result, $self->{provider}, $self->{model});
}

sub _request_json {
    my ($self, %args) = @_;
    my $mock = $ENV{MARK6_AI_MOCK_RESPONSE};
    return decode_json($mock) if defined $mock && $mock ne '';

    die "Unsupported AI provider: $self->{provider}" unless $self->{provider} eq 'openai';

    my $api_key = _env_value($self->{api_key_env}) || _file_value($self->{api_key_file});
    die "AI API key is not configured. Set $self->{api_key_env} or write the key file $self->{api_key_file}." if $api_key eq '';

    my $payload = JSON::PP->new->utf8->canonical->encode({
        model => $self->{model},
        input => [
            {
                role => 'system',
                content => $args{system},
            },
            {
                role => 'user',
                content => $args{prompt},
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
    return _decode_json_text($text);
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

sub default_api_key_file {
    my $home = $ENV{HOME} || eval { (getpwuid($<))[7] } || '';
    return '' if $home eq '';
    return "$home/.mark6_openai_key";
}

sub _file_value {
    my ($path) = @_;
    return '' unless defined $path && $path ne '';
    return '' if $path =~ /\0/;
    return '' unless -f $path;

    open my $fh, '<:raw', $path or return '';
    my $value = <$fh> || '';
    close $fh;
    $value =~ s/\A\s+|\s+\z//g;
    return $value;
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

sub _decode_json_text {
    my ($text) = @_;
    return JSON::PP->new->decode($text);
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

sub _normalize_body_result {
    my ($result, $provider, $model) = @_;
    return {
        body              => _clean_html($result->{body} || ''),
        provider          => $provider,
        model             => $model,
        last_processed_at => _iso_now(),
    };
}

sub _normalize_translation_result {
    my ($result, $provider, $model, $source_lang, $target_lang) = @_;
    return {
        title             => _clean_text($result->{title} || ''),
        description       => _clean_html($result->{description} || ''),
        body              => _clean_html($result->{body} || ''),
        source_lang       => $source_lang,
        target_lang       => $target_lang,
        provider          => $provider,
        model             => $model,
        last_processed_at => _iso_now(),
    };
}

sub _normalize_seo_result {
    my ($result, $provider, $model) = @_;
    my $base = _normalize_result($result, $provider, $model);
    $base->{diagnosis} = _clean_text($result->{diagnosis} || '');
    return $base;
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

sub _clean_html {
    my ($value) = @_;
    $value = '' unless defined $value;
    $value =~ s/^\s+|\s+$//g;
    return $value;
}

sub _iso_now {
    my @t = gmtime(time);
    return sprintf('%04d-%02d-%02dT%02d:%02d:%02dZ',
        $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0]);
}

1;
