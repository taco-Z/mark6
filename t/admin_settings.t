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
my $root = File::Spec->catdir('t', 'tmp_admin_settings');

remove_tree($root) if -d $root;
make_path(File::Spec->catdir($root, 'dat', 'sessions'));
write_json(File::Spec->catfile($root, 'dat', 'users.json'), { version => 1, users => [] });
write_json(File::Spec->catfile($root, 'dat', 'config.json'), {
    version => 1,
    site => { title => 'Before Site', language => 'ja', base_url => '' },
    features => { tags => JSON::PP::true, newest => JSON::PP::true, popular => JSON::PP::false, ai => JSON::PP::false },
    display => { articles_per_page => 20, mini_articles => 15 },
    nodes => {
        oita360 => {
            nav => JSON::PP::true,
            labels => { ja => '大分360', en => 'Oita 360' },
        },
    },
    kiosk => { provider => 'amazon', affiliate_tag => '' },
    ai => { provider => 'openai', model => 'gpt-5.2', api_key_env => 'MARK6_OPENAI_API_KEY', api_key_file => '' },
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

my $dashboard = run_cgi(
    script => File::Spec->catfile('admin', 'index.cgi'),
    method => 'GET',
    cookie => "mark6_session=$session_id",
);
like($dashboard, qr/settings\.cgi/, 'dashboard links to settings');

my $settings = run_cgi(
    script => File::Spec->catfile('admin', 'settings.cgi'),
    method => 'GET',
    cookie => "mark6_session=$session_id",
);
like($settings, qr/設定/, 'settings form renders');
like($settings, qr/Before Site/, 'settings form includes current site title');
like($settings, qr/name="ai_model"/, 'settings form includes AI model field');
like($settings, qr/name="ai_api_key_file"/, 'settings form includes AI key file field');
like($settings, qr/name="amazon_affiliate_tag"/, 'settings form includes Amazon Associate tag field');
like($settings, qr/name="node_id_1"/, 'settings form includes section ID field');
like($settings, qr/name="node_label_en_1"/, 'settings form includes English section label field');
unlike($settings, qr/name="feature_shop"/, 'settings form does not show old shop feature switch');
unlike($settings, qr/name="paypal_id"/, 'settings form does not show old shop section');
my ($csrf) = $settings =~ /name="csrf_token" value="([0-9a-f]+)"/;
ok($csrf, 'settings form includes csrf token');

my $save = run_cgi(
    script => File::Spec->catfile('admin', 'settings.cgi'),
    method => 'POST',
    cookie => "mark6_session=$session_id",
    body => form_data(
        csrf_token => $csrf,
        site_title => 'After Site',
        base_url => 'https://example.test',
        language => 'en',
        articles_per_page => 12,
        mini_articles => 7,
        feature_tags => 1,
        feature_ai => 1,
        node_id_1 => 'oita360',
        node_label_ja_1 => '大分360',
        node_label_en_1 => 'Oita 360',
        node_nav_1 => 1,
        node_id_2 => 'news',
        node_label_ja_2 => 'ニュース',
        node_label_en_2 => 'News',
        node_nav_2 => 1,
        amazon_affiliate_tag => 'mark6-test-22',
        ai_model => 'custom-model',
        ai_api_key_env => 'CUSTOM_OPENAI_KEY',
        ai_api_key_file => '/home/example/.mark6_openai_key',
    ),
);
like($save, qr/Location: settings\.cgi\?saved=1/, 'settings save redirects');

my $config = read_json(File::Spec->catfile($root, 'dat', 'config.json'));
is($config->{site}{title}, 'After Site', 'site title saved');
is($config->{site}{base_url}, 'https://example.test', 'base url saved');
is($config->{site}{language}, 'en', 'language saved');
is($config->{display}{articles_per_page}, 12, 'articles per page saved');
is($config->{display}{mini_articles}, 7, 'mini articles saved');
ok($config->{features}{tags}, 'tags feature saved true');
ok($config->{features}{ai}, 'ai feature saved true');
ok(!$config->{features}{newest}, 'unchecked newest saved false');
ok(!$config->{features}{popular}, 'unchecked popular saved false');
ok(!exists $config->{features}{shop}, 'old shop feature parameter removed');
ok(!exists $config->{shop}, 'old shop settings removed');
is($config->{kiosk}{provider}, 'amazon', 'Kiosk provider saved as Amazon');
is($config->{kiosk}{affiliate_tag}, 'mark6-test-22', 'Amazon Associate tag saved');
is($config->{nodes}{oita360}{labels}{en}, 'Oita 360', 'English section label saved');
ok($config->{nodes}{news}{nav}, 'second section nav flag saved');
is($config->{ai}{provider}, 'openai', 'ai provider saved');
is($config->{ai}{model}, 'custom-model', 'ai model saved');
is($config->{ai}{api_key_env}, 'CUSTOM_OPENAI_KEY', 'ai api key env saved');
is($config->{ai}{api_key_file}, '/home/example/.mark6_openai_key', 'ai api key file saved');

my $public = run_cgi(
    script => File::Spec->catfile('public', 'index.cgi'),
    method => 'GET',
    path_info => '/en/',
);
like($public, qr/<title>After Site<\/title>/, 'public page uses updated site title');
like($public, qr/href="https:\/\/example\.test\/en\/oita360\/">Oita 360<\/a>/, 'public page uses English section label in nav');
like($public, qr/href="https:\/\/example\.test\/en\/news\/">News<\/a>/, 'public page renders second section nav link');

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
    local $ENV{CONTENT_TYPE} = $args{content_type} || 'application/x-www-form-urlencoded';

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
