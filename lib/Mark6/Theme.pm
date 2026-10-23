package Mark6::Theme;
use strict;
use warnings;
use Mark6::CGI ();

sub presets {
    return {
        classic => { background => '#f2f2f2', panel => '#ffffff', text => '#111111', accent => '#087f8d', font => 'sans', width => 960 },
        cee => { background => '#edf3f8', panel => '#ffffff', text => '#152536', accent => '#1465a3', font => 'sans', width => 1080 },
        waremono => { background => '#f6f0e8', panel => '#fffdf9', text => '#322a25', accent => '#825035', font => 'serif', width => 960 },
        sati => { background => '#f0edf7', panel => '#ffffff', text => '#30283e', accent => '#705293', font => 'sans', width => 800 },
    };
}
sub normalize {
    my ($input) = @_;
    $input = {} unless ref($input) eq 'HASH';
    my $presets = presets();
    my $name = exists $presets->{$input->{preset} || ''} ? $input->{preset} : 'classic';
    my %theme = (%{$presets->{$name}}, preset => $name);
    for my $key (qw(background panel text accent)) {
        $theme{$key} = $input->{$key} if defined($input->{$key}) && $input->{$key} =~ /\A#[a-fA-F0-9]{6}\z/;
    }
    $theme{font} = $input->{font} if ($input->{font} || '') =~ /\A(?:sans|serif|mono)\z/;
    $theme{width} = 0 + $input->{width} if ($input->{width} || '') =~ /\A(?:720|800|960|1080|1200)\z/;
    return \%theme;
}
sub css {
    my ($input) = @_;
    return '' unless ref($input) eq 'HASH' && keys %$input;
    my $t = normalize($input);
    my %fonts = (sans => 'system-ui,sans-serif', serif => 'Georgia,serif', mono => 'monospace');
    return ':root{--bg:' . $t->{background} . ';--panel:' . $t->{panel} . ';--text:' . $t->{text}
        . ';--accent:' . $t->{accent} . ';--accent-strong:' . $t->{accent} . '}'
        . 'body{font-family:' . $fonts{$t->{font}} . '}.site-main{width:min(' . $t->{width} . 'px,calc(100% - 32px))}';
}
sub editor {
    my ($input) = @_;
    my $t = normalize($input);
    my $html = '<fieldset id="theme-editor"><legend>Site theme</legend><p>Choose a preset, then adjust and save. Preview changes stay here until saved.</p>';
    my %options = (preset => [qw(classic cee waremono sati)], font => [qw(sans serif mono)], width => [qw(720 800 960 1080 1200)]);
    for my $key (qw(preset font width)) {
        $html .= qq|<label>$key <select name="theme_$key">|;
        for my $v (@{$options{$key}}) {
            my $selected = "$t->{$key}" eq "$v" ? ' selected' : '';
            $html .= qq|<option value="$v"$selected>$v</option>|;
        }
        $html .= '</select></label>';
    }
    for my $key (qw(background panel text accent)) {
        $html .= qq|<label>$key <input type="color" name="theme_$key" value="$t->{$key}"></label>|;
    }
    $html .= '<iframe title="Theme preview" sandbox="" id="theme-preview" style="width:100%;height:260px;border:1px solid #ccc"></iframe></fieldset><script src="../public/assets/js/theme-editor.js" defer></script>';
    return $html;
}
1;
