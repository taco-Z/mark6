package Mark6::QualityReport;

use strict;
use warnings;
use utf8;
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Spec;
use JSON::PP ();
use Time::Piece;
use Mark6::Article;

my %SEVERITY_SCORE = (P0 => 40, P1 => 20, P2 => 5, P3 => 1, INFO => 0);
my %SEVERITY_RANK  = (P0 => 4, P1 => 3, P2 => 2, P3 => 1, INFO => 0, OK => 0);

sub new {
    my ($class, %args) = @_;
    my $root = $args{root} || '.';
    my $config = $args{config};
    $config = read_json_file(File::Spec->catfile($root, 'dat', 'config.json')) || {} unless ref($config);
    my $checker = ref($config->{content_checker}) eq 'HASH' ? $config->{content_checker} : {};
    my $profile = $args{profile} || $checker->{profile} || 'default';
    $profile = 'regional_media' if $profile eq 'oita360';
    return bless { root => $root, node => $args{node} || '', profile => $profile, config => $config, checker => $checker }, $class;
}

sub generate {
    my ($self) = @_;
    my $articles_dir = File::Spec->catdir($self->{root}, 'dat', 'articles');
    die "No article directory: $articles_dir\n" unless -d $articles_dir;
    my @files = sort glob File::Spec->catfile($articles_dir, '*.json');
    my @rows;
    my %counts = (files => scalar @files, parsed => 0, skipped => 0, parse_error => 0);
    for my $file (@files) {
        my ($content, $error) = read_json($file);
        if ($error) { $counts{parse_error}++; push @rows, parse_error_row($file, $error); next; }
        if (Mark6::Article::content_type($content) eq 'page') { $counts{skipped}++; next; }
        next if $self->{node} ne '' && ($content->{node} || '') ne $self->{node};
        $counts{parsed}++;
        push @rows, $self->analyze_content($content, basename_only($file));
    }
    @rows = sort { $b->{score} <=> $a->{score} || $a->{title} cmp $b->{title} || $a->{file} cmp $b->{file} } @rows;
    my (%priority_counts, %status_counts);
    for my $row (@rows) {
        $status_counts{$row->{status}}++;
        $priority_counts{$_->{severity}}++ for @{$row->{issue_items} || []};
        $priority_counts{OK}++ if !grep { $_->{severity} ne 'INFO' } @{$row->{issue_items} || []};
    }
    return { root => $self->{root}, node => $self->{node}, profile => $self->{profile}, articles_dir => $articles_dir,
        rows => \@rows, counts => \%counts, priority_counts => \%priority_counts, status_counts => \%status_counts };
}

sub analyze_article { return analyze_content(@_); }

sub analyze_content {
    my ($self, $content, $file) = @_;
    my @issues;
    my $status = text($content->{status});
    my $default_lang = Mark6::Article::default_lang($content, $self->{config});
    my @langs = $self->content_languages($content, $default_lang);
    my $default = language_data($content, $default_lang);
    my $title = text($default->{title} || $content->{title});
    my $description = text($default->{description} || $content->{intro} || $content->{description});
    my $body = text($default->{body} || $content->{body});
    my $slug = text($content->{slug});
    my $published = $status eq 'published';
    my $profile_names = $self->profiles_for($content);

    $self->add_issue(\@issues, 'title_missing', 'P0', 'title', 'Title is required.') if $title eq '';
    if ($body eq '') { $self->add_issue(\@issues, 'body_missing', $published ? 'P0' : 'P3', 'body', 'Body is required for published content.'); }
    elsif ($self->below_limit('body', $body, $default_lang)) { $self->add_issue(\@issues, 'body_short', 'P2', 'body', 'Body is shorter than the configured minimum.'); }
    $self->add_issue(\@issues, 'slug_missing', 'P1', 'slug', 'Slug is required.') if $slug eq '';
    $self->add_issue(\@issues, 'slug_generic', 'P2', 'slug', 'Slug looks generic.') if $self->generic_slug($slug);
    if ($description eq '') {
        $self->add_issue(\@issues, 'description_missing', $published ? 'P1' : 'P3', 'description', 'Description is missing.');
    } else {
        $self->add_issue(\@issues, 'description_short', 'P2', 'description', 'Description is shorter than the configured minimum.') if $self->below_limit('description', $description, $default_lang);
        $self->add_issue(\@issues, 'description_generic', 'P2', 'description', 'Description appears generic.') if $self->generic_description($description, $title, $content);
    }
    $self->add_issue(\@issues, 'title_generic', 'P2', 'title', 'Title looks generic.') if $self->generic_title($title);

    for my $lang (@langs) {
        next if $lang eq $default_lang;
        my $localized = language_data($content, $lang);
        $self->add_issue(\@issues, 'translation_missing', $published ? 'P1' : 'P3', "langs.$lang.title", "Translation title is missing for $lang.") if text($localized->{title}) eq '';
        $self->add_issue(\@issues, 'translation_body_missing', $published ? 'P1' : 'P3', "langs.$lang.body", "Translation body is missing for $lang.") if text($localized->{body}) eq '';
        $self->add_issue(\@issues, 'translation_description_missing', $published ? 'P2' : 'P3', "langs.$lang.description", "Translation description is missing for $lang.") if text($localized->{description}) eq '';
    }

    $self->profile_checks(\@issues, $content, $profile_names, $status);
    my $source = ref($content->{source}) eq 'HASH' ? $content->{source} : {};
    $self->add_issue(\@issues, 'original_description_missing', 'INFO', 'source.original_description', 'Original description was not available.', 'provenance') if text($source->{original_description}) eq '';

    my ($score, %priority_counts) = (0);
    for my $issue (@issues) { $score += $issue->{score}; $priority_counts{$issue->{severity}}++; }
    my $priority = highest_priority(\@issues);
    my $row_status = $priority eq 'P0' ? 'BLOCK' : $priority eq 'P1' ? 'FIX' : $priority eq 'P2' ? 'REVIEW' : 'OK';
    my @notes = map { $_->{message} } grep { $_->{severity} eq 'INFO' } @issues;
    return { file => $file, id => text($content->{id}), title => $title, slug => $slug, node => text($content->{node}),
        url => Mark6::Article::public_path($content, $default_lang, $self->{config}), score => $score, risk_score => $score,
        status => $row_status, priority => $priority, issues => [map { $_->{message} } @issues], issue_items => \@issues,
        notes => \@notes, p0_count => $priority_counts{P0} || 0, p1_count => $priority_counts{P1} || 0,
        p2_count => $priority_counts{P2} || 0, p3_count => $priority_counts{P3} || 0, info_count => $priority_counts{INFO} || 0,
        profile => join(',', @{$profile_names}), category_status => category_status(\@issues) };
}

sub profile_checks {
    my ($self, $issues, $content, $profile_names, $status) = @_;
    my $profiles = ref($self->{checker}{profiles}) eq 'HASH' ? $self->{checker}{profiles} : {};
    my $meta = ref($content->{article}) eq 'HASH' ? $content->{article} : {};
    my $caps = ref($content->{capabilities}) eq 'ARRAY' ? { map { $_ => 1 } @{$content->{capabilities}} } : {};
    $caps->{$_} = 1 for grep { ref($content->{$_}) } qw(location media gallery);
    $caps->{video} = 1 if ref($content->{media}) eq 'HASH' && ($content->{media}{type} || '') eq 'video';
    for my $profile (@{$profile_names}) {
        my $rules = ref($profiles->{$profile}) eq 'HASH' ? $profiles->{$profile} : {};
        my @required = ref($rules->{required_metadata}) eq 'ARRAY' ? @{$rules->{required_metadata}} : ();
        for my $path (@required) {
            next if value_at($content, $path) ne '' || value_at($meta, $path) ne '';
            my $rule = ref($rules->{metadata_rules}) eq 'HASH' && ref($rules->{metadata_rules}{$path}) eq 'HASH' ? $rules->{metadata_rules}{$path} : {};
            my $level = $rule->{level} || 'recommended';
            my $severity = $level eq 'required' ? ($status eq 'published' ? 'P1' : 'P3') : $level eq 'recommended' ? 'P3' : 'INFO';
            $self->add_issue($issues, code_for_path($path), $severity, $path, "$path is missing.", 'metadata');
        }
        my $types = ref($rules->{location_required_for_types}) eq 'ARRAY' ? { map { lc($_) => 1 } @{$rules->{location_required_for_types}} } : {};
        my $type = lc(text($meta->{type}));
        if ($types->{$type}) {
            my $location = ref($meta->{location}) eq 'HASH' ? $meta->{location} : {};
            $self->add_issue($issues, 'location_city_missing', 'P3', 'article.location.city', 'location.city is missing.', 'metadata') if text($location->{city}) eq '';
        }
        my $required_caps = $rules->{require_capabilities};
        if (ref($required_caps) eq 'HASH') {
            for my $cap (keys %{$required_caps}) {
                next unless $caps->{$cap};
                my $path = $required_caps->{$cap};
                $self->add_issue($issues, "${cap}_source_missing", 'P1', $path, "$path is missing.", 'integrity') if value_at($content, $path) eq '';
            }
        }
    }
    if ($caps->{video} || (ref($content->{media}) eq 'HASH' && ($content->{media}{type} || '') eq 'video')) {
        my $media = ref($content->{media}) eq 'HASH' ? $content->{media} : {};
        $self->add_issue($issues, 'video_source_missing', 'P1', 'media.id', 'Video source is missing.', 'integrity') if text($media->{id} || $media->{url} || $content->{video_id}) eq '';
    }
}

sub profiles_for {
    my ($self, $content) = @_;
    my @profiles = ref($content->{content_profiles}) eq 'ARRAY' ? @{$content->{content_profiles}} : text($content->{content_profile}) ne '' ? ($content->{content_profile}) : ($self->{profile});
    @profiles = ('default') unless @profiles;
    @profiles = map { $_ eq 'oita360' ? 'regional_media' : $_ } @profiles;
    return \@profiles;
}

sub content_languages {
    my ($self, $content, $default) = @_;
    my $site_langs = $self->{config}{site}{langs};
    my @langs = ref($site_langs) eq 'ARRAY' ? @{$site_langs} : ();
    push @langs, $default unless @langs;
    push @langs, $default;
    my %seen;
    return grep { defined($_) && $_ ne '' && !$seen{$_}++ } @langs;
}

sub add_issue {
    my ($self, $issues, $code, $severity, $field, $message, $category) = @_;
    push @{$issues}, { code => $code, severity => $severity, score => $SEVERITY_SCORE{$severity} || 0, field => $field || '', category => $category || issue_category($code), message => $message };
}

sub below_limit {
    my ($self, $field, $value, $lang) = @_;
    my $limits = ref($self->{checker}{text_limits}) eq 'HASH' ? $self->{checker}{text_limits} : {};
    my $lang_limits = ref($limits->{$lang}) eq 'HASH' ? $limits->{$lang} : {};
    my $defaults = ref($limits->{default}) eq 'HASH' ? $limits->{default} : {};
    my $key = $field . '_min_chars';
    my $minimum = exists($lang_limits->{$key}) ? $lang_limits->{$key} : ($defaults->{$key} || ($field eq 'description' ? 100 : 500));
    return length(plain_text($value)) < $minimum;
}

sub generic_title {
    my ($self, $value) = @_;
    my $phrases = $self->{checker}{generic_phrases};
    $phrases = [qw(test article untitled sample video)] unless ref($phrases) eq 'ARRAY';
    return $value ne '' && scalar grep { lc($value) eq lc($_) } @{$phrases};
}

sub generic_description {
    my ($self, $description, $title, $content) = @_;
    my $phrases = $self->{checker}{generic_description_phrases};
    $phrases = ['this place is introduced', '詳しく紹介します', '観光におすすめです'] unless ref($phrases) eq 'ARRAY';
    return 1 if scalar grep { $_ ne '' && index(lc($description), lc($_)) >= 0 } @{$phrases} && length($description) < 120;
    return 0 if $title ne '' && index(lc($description), lc($title)) >= 0;
    return 0 if ref($content->{capabilities}) eq 'ARRAY' && @{$content->{capabilities}};
    return 0;
}

sub generic_slug {
    my ($self, $slug) = @_;
    my $rule = $self->{checker}{slug_check};
    return 0 if $slug eq '' || (ref($rule) eq 'HASH' && exists($rule->{enabled}) && !$rule->{enabled});
    return 1 if $slug =~ /\A(?:test|sample|article|post)(?:[-_][0-9]+)?\z/i;
    my $allow_id_slug = ref($rule) eq 'HASH' && exists($rule->{allow_id_slug}) ? $rule->{allow_id_slug} : 1;
    return 1 if $slug =~ /\Avideo-[0-9A-Za-z_-]{8,}\z/i && !$allow_id_slug;
    return 0;
}

sub write_markdown {
    my ($report, $path) = @_;
    make_path(dirname($path)) unless -d dirname($path);
    my @lines = ('# Content quality report', '', '- generated_at: ' . localtime->datetime, "- profile: `$report->{profile}`", "- node: `" . ($report->{node} || '(all)') . '`', "- scanned_contents: $report->{counts}{parsed}", "- parse_errors: $report->{counts}{parse_error}", '');
    push @lines, '## Summary', '', map { "- $_: " . ($report->{priority_counts}{$_} || 0) } qw(P0 P1 P2 P3 INFO OK);
    push @lines, '', '### Status', '', (map { "- $_: " . ($report->{status_counts}{$_} || 0) } qw(BLOCK FIX REVIEW OK)), '';
    push @lines, '## First fixes', '';
    my @needs = grep { $_->{status} ne 'OK' } @{$report->{rows}};
    if (@needs) { for my $row (@needs[0 .. (@needs > 24 ? 24 : $#needs)]) { push @lines, "### [$row->{status}] $row->{title}", '', "- file: `$row->{file}`", "- url: `$row->{url}`", "- risk_score: $row->{risk_score}", "- issues: " . (join('; ', @{$row->{issues}}) || 'OK'), ''; } }
    else { push @lines, 'No obvious issues found.', ''; }
    push @lines, '## All contents', '', '| priority | score | status | title | file | issues |', '| --- | ---: | --- | --- | --- | --- |';
    for my $row (@{$report->{rows}}) { push @lines, join(' | ', '', md_cell($row->{priority}), $row->{score}, md_cell($row->{status}), md_cell($row->{title}), '`' . $row->{file} . '`', md_cell(join('; ', @{$row->{issues}}) || 'OK'), ''); }
    write_text($path, join("\n", @lines) . "\n");
}

sub write_csv {
    my ($report, $path) = @_;
    make_path(dirname($path)) unless -d dirname($path);
    my $body = csv_row(qw(priority score status p0_count p1_count p2_count p3_count info_count file id node slug url title issues notes));
    for my $row (@{$report->{rows}}) { $body .= csv_row(@{$row}{qw(priority score status p0_count p1_count p2_count p3_count info_count file id node slug url title)}, join('; ', @{$row->{issues}}), join('; ', @{$row->{notes}})); }
    write_text($path, $body);
}

sub default_markdown_path { my ($root, $profile) = @_; return File::Spec->catfile($root, 'logs', $profile eq 'regional_media' || $profile eq 'oita360' ? 'regional_media_quality_report.md' : 'article_quality_report.md'); }
sub default_csv_path { my ($root, $profile) = @_; return File::Spec->catfile($root, 'logs', $profile eq 'regional_media' || $profile eq 'oita360' ? 'regional_media_quality_report.csv' : 'article_quality_report.csv'); }
sub parse_error_row { my ($file, $error) = @_; my $issue = { code => 'json_invalid', severity => 'P0', score => 40, field => '', category => 'integrity', message => "JSON parse error: $error" }; return { file => basename_only($file), id => '', title => '', slug => '', node => '', url => '', score => 40, risk_score => 40, status => 'BLOCK', priority => 'P0', issues => [$issue->{message}], issue_items => [$issue], notes => [], p0_count => 1, p1_count => 0, p2_count => 0, p3_count => 0, info_count => 0 }; }
sub highest_priority { my ($issues) = @_; my $best = 'OK'; for my $issue (@{$issues}) { $best = $issue->{severity} if ($SEVERITY_RANK{$issue->{severity}} || 0) > ($SEVERITY_RANK{$best} || 0); } return $best; }
sub category_status { my ($issues) = @_; my %result = map { $_ => 'OK' } qw(integrity content seo metadata provenance); for my $issue (@{$issues}) { next if $issue->{severity} eq 'INFO'; my $category = $issue->{category} || 'content'; my $next = $issue->{severity} eq 'P0' ? 'BLOCK' : $issue->{severity} eq 'P1' ? 'FIX' : $issue->{severity} eq 'P2' ? 'REVIEW' : 'OK'; $result{$category} = $next if ($SEVERITY_RANK{$next} || 0) > ($SEVERITY_RANK{$result{$category} || 'OK'} || 0); } return \%result; }
sub issue_category { my ($code) = @_; return 'provenance' if $code =~ /original/; return 'seo' if $code =~ /description|title_generic/; return 'content' if $code =~ /short|translation/; return 'metadata' if $code =~ /(?:location|city|series|tag)/; return 'integrity' if $code =~ /(?:missing|invalid|json|slug|video|body)/; return 'content'; }
sub code_for_path { my ($path) = @_; $path =~ s/\./_/g; return $path . '_missing'; }
sub language_data { my ($content, $lang) = @_; return ref($content->{langs}) eq 'HASH' && ref($content->{langs}{$lang}) eq 'HASH' ? $content->{langs}{$lang} : {}; }
sub value_at { my ($value, $path) = @_; for my $part (split /\./, $path || '') { return '' unless ref($value) eq 'HASH' && exists $value->{$part}; $value = $value->{$part}; } return ref($value) ? '' : text($value); }
sub read_json { my ($path) = @_; open my $fh, '<:raw', $path or return (undef, "Cannot read: $!"); local $/; my $raw = <$fh>; close $fh; my $json = eval { JSON::PP->new->utf8->decode($raw) }; return (undef, $@ || 'Invalid JSON') if $@ || ref($json) ne 'HASH'; return ($json, ''); }
sub read_json_file { my ($path) = @_; my ($json) = read_json($path); return $json; }
sub write_text { my ($path, $body) = @_; open my $fh, '>:encoding(UTF-8)', $path or die "Cannot write $path: $!\n"; print {$fh} $body; close $fh; }
sub csv_row { return join(',', map { csv_escape($_) } @_) . "\n"; }
sub csv_escape { my ($value) = @_; $value = '' unless defined $value; $value =~ s/"/""/g; return qq("$value"); }
sub md_cell { my ($value) = @_; $value = '' unless defined $value; $value =~ s/\|/\\|/g; $value =~ s/\r?\n/ /g; return $value; }
sub text { my ($value) = @_; return '' unless defined $value; $value = "$value"; $value =~ s/^\s+|\s+$//g; return $value; }
sub plain_text { my ($value) = @_; $value = text($value); $value =~ s/<[^>]+>/ /g; $value =~ s/&(?:nbsp|amp|lt|gt);/ /g; $value =~ s/\s+/ /g; $value =~ s/^\s+|\s+$//g; return $value; }
sub basename_only { my ($path) = @_; $path =~ s{\\}{/}g; $path =~ s{.*/}{}; return $path; }

1;
