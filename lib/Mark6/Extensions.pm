package Mark6::Extensions;
use strict;
use warnings;
use Cwd qw(abs_path);
use File::Basename qw(dirname);

# Extensions are application code, never loaded from the data store.
my $code_root = abs_path(dirname(__FILE__) . '/../..');
sub installed {
    my ($name) = @_;
    return 0 unless defined($name) && $name =~ /\A[a-z][a-z0-9_-]*\z/;
    return -f "$code_root/extensions/$name/Extension.pm";
}
sub load {
    my ($name) = @_;
    return undef unless installed($name);
    my $extension = do "$code_root/extensions/$name/Extension.pm";
    return ref($extension) eq 'HASH' ? $extension : undef;
}
sub dispatch {
    my ($name, %args) = @_;
    my $settings = ($args{config}{extensions} || {})->{$name} || {};
    my $extension;
    if (($settings->{enabled} || '') eq '1') {
        $extension = load($name);
    }
    unless ($extension && ref($extension->{run}) eq 'CODE') {
        print "Status: 404\r\nContent-Type: application/json; charset=utf-8\r\nCache-Control: no-store\r\n\r\n{\"error\":\"not_found\"}";
        return;
    }
    $extension->{run}->(%args);
}
1;
