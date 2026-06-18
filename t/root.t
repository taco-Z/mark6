use strict;
use warnings;
use Test::More;
use File::Path qw(make_path remove_tree);
use File::Spec;
use Cwd qw(abs_path getcwd);
use Mark6::Root;

my $root = File::Spec->catdir('t', 'tmp_root_resolution');
remove_tree($root) if -d $root;

my $site = File::Spec->catdir($root, 'mark6');
my $admin = File::Spec->catdir($site, 'admin');
my $public = File::Spec->catdir($site, 'public');

make_path(File::Spec->catdir($site, 'dat'));
make_path(File::Spec->catdir($admin, 'dat'));
make_path($public);

write_file(File::Spec->catfile($site, 'dat', 'users.json'), '{"version":1,"users":[]}');
write_file(File::Spec->catfile($site, 'dat', 'config.json'), '{"version":1}');
write_file(File::Spec->catfile($admin, 'dat', 'users.json'), '{"version":1,"users":[{"bad":true}]}');
write_file(File::Spec->catfile($admin, 'articles.cgi'), '');
write_file(File::Spec->catfile($public, 'index.cgi'), '');

my $expected_site = normalize($site);
my $old_cwd = getcwd();
chdir $admin or die "Cannot chdir $admin: $!";

is(
    normalize(Mark6::Root::default_root(
        findbin => $admin,
        script  => File::Spec->catfile($admin, 'articles.cgi'),
        marker  => 'dat/users.json',
    )),
    $expected_site,
    'admin CGI resolves site root even when admin/dat exists',
);

is(
    normalize(Mark6::Root::default_root(
        findbin => $public,
        script  => File::Spec->catfile($public, 'index.cgi'),
        marker  => 'dat/config.json',
    )),
    $expected_site,
    'public CGI resolves site root from script location',
);

chdir $old_cwd or die "Cannot chdir $old_cwd: $!";
remove_tree($root);
done_testing;

sub write_file {
    my ($path, $body) = @_;
    open my $fh, '>:raw', $path or die "Cannot write $path: $!";
    print {$fh} $body;
    close $fh;
}

sub normalize {
    my ($path) = @_;
    return abs_path($path);
}
