use strict;
use warnings;
use Test::More;
use File::Path qw(make_path remove_tree);
use File::Spec;
use JSON::PP ();
use Mark6::Lang;

my $root = File::Spec->catdir('t', 'tmp_lang');
remove_tree($root) if -d $root;
make_path(File::Spec->catdir($root, 'dat', 'lang'));

write_json(File::Spec->catfile($root, 'dat', 'config.json'), {
    version => 1,
    site => { language => 'ja' },
});
write_json(File::Spec->catfile($root, 'dat', 'lang', 'ja.json'), {
    'admin.nav.dashboard' => 'ダッシュボード',
});

my $lang = Mark6::Lang->new(root => $root);
is($lang->code, 'ja', 'language code loaded from config');
is($lang->t('admin.nav.dashboard'), 'ダッシュボード', 'string loaded from language file');
is($lang->t('admin.nav.logout'), 'ログアウト', 'default Japanese fallback is available');
is($lang->t('missing.key', 'fallback'), 'fallback', 'fallback is used for missing keys');

remove_tree($root);
done_testing;

sub write_json {
    my ($path, $data) = @_;
    open my $fh, '>:raw', $path or die "Cannot write $path: $!";
    print {$fh} JSON::PP->new->utf8->canonical->pretty->encode($data);
    close $fh;
}
