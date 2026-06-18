use strict;
use warnings;
use Test::More;
use File::Path qw(make_path remove_tree);
use File::Spec;
use JSON::PP ();
use Encode qw(decode encode);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);

my $perl = $^X;
my $root = File::Spec->catdir('t', 'tmp_admin_media');

remove_tree($root) if -d $root;
make_path(File::Spec->catdir($root, 'dat', 'articles'));
make_path(File::Spec->catdir($root, 'dat', 'media'));
make_path(File::Spec->catdir($root, 'dat', 'sessions'));
write_json(File::Spec->catfile($root, 'dat', 'users.json'), { version => 1, users => [] });
write_json(File::Spec->catfile($root, 'dat', 'config.json'), {
    version => 1,
    site => { title => 'MARK6 Test', language => 'ja', base_url => '' },
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

my $media_page = run_cgi(
    script => File::Spec->catfile('admin', 'media.cgi'),
    method => 'GET',
    cookie => "mark6_session=$session_id",
);
like($media_page, qr/Media/, 'media page renders');
my ($csrf) = $media_page =~ /name="csrf_token" value="([0-9a-f]+)"/;
ok($csrf, 'media form includes csrf token');

my $png = "\x89PNG\r\n\x1a\nfake";
my ($body, $boundary) = multipart_body(
    fields => {
        command => 'upload',
        csrf_token => $csrf,
    },
    file => {
        field => 'file',
        filename => 'sample.png',
        content_type => 'image/png',
        content => $png,
    },
);

my $upload = run_cgi(
    script => File::Spec->catfile('admin', 'media.cgi'),
    method => 'POST',
    cookie => "mark6_session=$session_id",
    body => $body,
    content_type => "multipart/form-data; boundary=$boundary",
);
like($upload, qr/Location: media\.cgi/, 'upload redirects to media list');

my @media_files = glob(File::Spec->catfile($root, 'dat', 'media', '*.json'));
is(scalar @media_files, 1, 'media metadata written');
my $media = read_json($media_files[0]);
my $uploaded_path = File::Spec->catfile($root, split('/', $media->{path}));
is($media->{original_filename}, 'sample.png', 'metadata keeps original filename');
like($media->{path}, qr{\Aimg/uploads/\d{4}/\d{2}/}, 'metadata path is under img/uploads');
ok(-e $uploaded_path, 'uploaded image file written');

my $media_after_upload = run_cgi(
    script => File::Spec->catfile('admin', 'media.cgi'),
    method => 'GET',
    cookie => "mark6_session=$session_id",
);
like($media_after_upload, qr/onsubmit="return confirm\('Delete this media file\?'\);"/, 'media delete confirms before submit');

my $articles_form = run_cgi(
    script => File::Spec->catfile('admin', 'articles.cgi'),
    method => 'GET',
    query => 'command=new',
    cookie => "mark6_session=$session_id",
);
like($articles_form, qr/sample\.png/, 'article form offers uploaded media');

my ($article_csrf) = $articles_form =~ /name="csrf_token" value="([0-9a-f]+)"/;
my $save_article = run_cgi(
    script => File::Spec->catfile('admin', 'articles.cgi'),
    method => 'POST',
    cookie => "mark6_session=$session_id",
    body => form_data(
        command => 'save',
        id => 'image-article',
        csrf_token => $article_csrf,
        title => '画像記事',
        status => 'published',
        tags => '',
        image => $media->{path},
        image_manual => '',
        intro => '',
        body => '<p>body</p>',
    ),
);
like($save_article, qr/Location: articles\.cgi/, 'article with media saves');

my $public = run_cgi(
    script => File::Spec->catfile('public', 'index.cgi'),
    method => 'GET',
    query => 'order=focus&tar=image-article',
);
like($public, qr/src="\/img\/uploads\//, 'public image src uses upload path');

my ($media_id) = $media_files[0] =~ /([^\\\/]+)\.json\z/;
my ($delete_body, $delete_boundary) = multipart_body(
    fields => {
        command => 'delete',
        csrf_token => $csrf,
        id => $media_id,
    },
);
my $delete = run_cgi(
    script => File::Spec->catfile('admin', 'media.cgi'),
    method => 'POST',
    cookie => "mark6_session=$session_id",
    body => $delete_body,
    content_type => "multipart/form-data; boundary=$delete_boundary",
);
like($delete, qr/Location: media\.cgi/, 'delete redirects to media list');

ok(!-e $media_files[0], 'media delete removes metadata JSON');
ok(!-e $uploaded_path, 'media delete removes uploaded image file');

remove_tree($root);
done_testing;

sub run_cgi {
    my (%args) = @_;
    local $ENV{MARK6_ROOT} = $root;
    local $ENV{REQUEST_METHOD} = $args{method} || 'GET';
    local $ENV{QUERY_STRING} = $args{query} || '';
    local $ENV{HTTP_COOKIE} = $args{cookie} || '';
    local $ENV{HTTPS} = '';
    local $ENV{CONTENT_TYPE} = $args{content_type} || 'application/x-www-form-urlencoded';

    my $body = $args{body} || '';
    local $ENV{CONTENT_LENGTH} = length($body);

    my $err = gensym;
    my $pid = open3(my $in, my $out, $err, $perl, $args{script});
    binmode $in;
    print {$in} $body if $body ne '';
    close $in;
    my $output = do { local $/; <$out> };
    my $error = do { local $/; <$err> };
    waitpid($pid, 0);
    die $error if ($? >> 8) != 0;

    return decode('UTF-8', $output || '');
}

sub multipart_body {
    my (%args) = @_;
    my $boundary = '----mark6testboundary';
    my $body = '';
    for my $name (sort keys %{$args{fields} || {}}) {
        $body .= "--$boundary\r\n";
        $body .= qq|Content-Disposition: form-data; name="$name"\r\n\r\n|;
        $body .= $args{fields}{$name} . "\r\n";
    }
    if ($args{file}) {
        my $file = $args{file};
        $body .= "--$boundary\r\n";
        $body .= qq|Content-Disposition: form-data; name="$file->{field}"; filename="$file->{filename}"\r\n|;
        $body .= "Content-Type: $file->{content_type}\r\n\r\n";
        $body .= $file->{content} . "\r\n";
    }
    $body .= "--$boundary--\r\n";
    return wantarray ? ($body, $boundary) : $body;
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
