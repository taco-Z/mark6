use strict;
use warnings;
use utf8;
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
    'admin.nav.dashboard' => '管理トップ',
});

my $lang = Mark6::Lang->new(root => $root);
is($lang->code, 'ja', 'language code loaded from config');
is($lang->t('admin.nav.dashboard'), '管理トップ', 'string loaded from language file');
is($lang->t('admin.nav.logout'), 'ログアウト', 'default Japanese fallback is available');
is($lang->t('missing.key', 'fallback'), 'fallback', 'fallback is used for missing keys');

write_json(File::Spec->catfile($root, 'dat', 'config.json'), {
    version => 1,
    site => { language => 'en' },
});

my $en = Mark6::Lang->new(root => $root);
is($en->code, 'en', 'English language code loaded from config');
is($en->t('admin.nav.dashboard'), 'Dashboard', 'default English strings are available');
is($en->t('admin.nav.view_site'), 'View Site', 'English nav strings are used');

remove_tree($root);
done_testing;

sub write_json {
    my ($path, $data) = @_;
    open my $fh, '>:raw', $path or die "Cannot write $path: $!";
    print {$fh} JSON::PP->new->utf8->canonical->pretty->encode($data);
    close $fh;
}
