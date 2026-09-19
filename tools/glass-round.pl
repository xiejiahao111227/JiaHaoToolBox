#!/usr/bin/perl
# 给输入控件与按钮补上 hc:BorderElement.CornerRadius，让 HandyControl 的基样式把边框也圆过来。
use strict;
use warnings;

my %want = map { $_ => 1 } qw(TextBox ComboBox ListBox PasswordBox GroupBox Button ToggleButton DatePicker);
my $n = 0;
local $/;
my $xaml = <>;
$xaml =~ s{<([A-Za-z][\w.]*)([^<>]*)>}{
    my ($tag, $attrs) = ($1, $2);
    if ($want{$tag} && $attrs !~ /BorderElement\.CornerRadius/) {
        my $r = $tag eq 'GroupBox' ? 16 : $tag eq 'ListBox' ? 14 : 10;
        $n++;
        "<$tag hc:BorderElement.CornerRadius=\"$r\"$attrs>";
    } else { "<$tag$attrs>" }
}gse;
print STDERR "rounded: $n\n";
print $xaml;
