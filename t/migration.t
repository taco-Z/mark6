use strict;
use warnings;
use Test::More;
use File::Path qw(make_path remove_tree);
use File::Spec;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Mark6::Mark5Migration;

my $root = File::Spec->catdir($FindBin::Bin, 'tmp_migration');
my $from = File::Spec->catdir($root, 'mark5');
my $to   = File::Spec->catdir($root, 'mark6');

remove_tree($root) if -d $root;
make_path(File::Spec->catdir($from, 'dat'));
make_path($to);

write_file(File::Spec->catfile($from, 'dat', 'ini.cgi'), join("\n",
    'site_title==Old Site',
    'number_miniart==9',
    'tag_sw==1',
    'shop_sw==0',
    'news_sw==1',
    'rank_sw==1',
));

write_file(File::Spec->catfile($from, 'dat', 'index.cgi'), join("\n",
    'title==Welcome',
    'body==Line<br>Two',
    'index_sw==1',
));

write_file(File::Spec->catfile($from, 'dat', 'article.cgi'), join("\n",
    '1710000000==perl,cms==pic.jpg==A<equal>B==Intro<br>Text==Body<return>Text==42==1',
));

write_file(File::Spec->catfile($from, 'dat', 'user.cgi'), join("\n",
    '1710000001==master==admin==abLegacyHash',
));

my $report = Mark6::Mark5Migration->new(from => $from, to => $to)->run;

ok(-e File::Spec->catfile($to, 'dat', 'config.json'), 'config migrated');
ok(-e File::Spec->catfile($to, 'dat', 'home.json'), 'home migrated');
ok(-e File::Spec->catfile($to, 'dat', 'articles', '1710000000.json'), 'article migrated');
ok(-e File::Spec->catfile($to, 'dat', 'users.json'), 'users migrated');
ok(-e File::Spec->catfile($to, 'dat', 'migration_report.json'), 'report written');
ok(grep({ $_ eq 'dat/config.json' } @{$report->{written}}), 'report includes config');

remove_tree($root);
done_testing;

sub write_file {
    my ($path, $body) = @_;
    open my $fh, '>:encoding(UTF-8)', $path or die "Cannot write $path: $!";
    print {$fh} $body, "\n";
    close $fh;
}

