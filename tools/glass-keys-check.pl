#!/usr/bin/perl
# 校验主题字典的键集一致性：所有 Glass* 语义键必须在每本字典里都存在，
# 否则换字典后 DynamicResource 会静默失效（控件拿到未设值的属性，深色底上尤其难发现）。
# 用法: perl tools/glass-keys-check.pl
use strict; use warnings;
my $dir = "JiaHaoToolBox";
my @dicts = ("Glass.Light.xaml", "Glass.Dark.xaml", "Glass.Classic.xaml");

sub keys_of {
    my ($f) = @_;
    open my $fh, "<", "$dir/Theme/$f" or die "读不到 $f: $!";
    my %k;
    while (<$fh>) { $k{$1} = 1 while /x:Key="([^"]+)"/g; }
    return \%k;
}

# XAML 里引用的 Glass* 键
my %used;
open my $x, "<", "$dir/MainWindow.xaml" or die "$!";
while (<$x>) {
    $used{$1} = 1 while /DynamicResource (Glass[A-Za-z0-9_]*)/g;
    $used{$1} = 1 while /DynamicResource (RegionBrush|PrimaryTextBrush|SecondaryTextBrush|BorderBrush|PrimaryBrush)/g;
}
close $x;
# 代码里按索引取的键
open my $c, "<", "$dir/MainWindow.GlassTheme.cs" or die "$!";
while (<$c>) { $used{$1} = 1 while /\[\s*"(Glass[A-Za-z0-9_]*)"\s*\]/g; }
close $c;

my @missing;
for my $d (@dicts) {
    my $k = keys_of($d);
    for my $u (sort keys %used) {
        push @missing, "$d 缺 $u" unless exists $k->{$u};
    }
}
# 经典字典不该覆盖 HandyControl 的键：覆盖了就等于没有上游默认配色
my $ck = keys_of("Glass.Classic.xaml");
my @hc_over = grep { $_ !~ /^Glass/ } sort keys %$ck;

my %lk = %{ keys_of("Glass.Light.xaml") };
my %dk = %{ keys_of("Glass.Dark.xaml") };
my @asym = (grep { !$dk{$_} } sort keys %lk), (grep { !$lk{$_} } sort keys %dk);

printf "XAML/代码引用的 Glass* 键: %d 个\n", scalar keys %used;
printf "键数  Light=%d Dark=%d Classic=%d\n", scalar keys %lk, scalar keys %dk, scalar keys %$ck;
print "Light/Dark 不对称: @asym\n" if @asym;
print "Classic 里多余的 HandyControl 覆盖键(应为空): @hc_over\n" if @hc_over;
if (@missing) { print "缺失:\n  ", join("\n  ", @missing), "\n"; exit 1 }
print "键集校验通过\n";
