#!/usr/bin/perl
# Style/Setter 上的写死配色：默认只报告，加 --apply 才落盘。
# 判定沿用元素的样式目标类型，按钮系的实体蓝底保持不动。
use strict;
use warnings;
use POSIX qw();

my $apply = grep { $_ eq '--apply' } @ARGV;
@ARGV = grep { $_ ne '--apply' } @ARGV;

require './tools/glass-palette.pl';
my ($near_white, $blue_chip, $gray_fill, $btn_blue, $gray_border, $blue_border, $dark_text, $mid_text, $blue_text) = glass_palette();

my %field_el = map { $_ => 1 } qw(TextBox ComboBox PasswordBox ListBox DataGrid TreeView RichTextBox);
my %btn_fam  = map { $_ => 1 } qw(Button ToggleButton RepeatButton RadioButton);
sub klass { my ($v, @list) = @_; for (@list) { return 1 if lc($_) eq lc($v) } return 0 }

local $/;
my @lines = split /\n/, scalar(<>), -1;
my $target = '';
my $style_bg = '';
my @report;
for my $i (0 .. $#lines) {
    my $ln = $lines[$i];
    if ($ln =~ /<Style\b/) { ($target, $style_bg) = ('', '') }
    if ($ln =~ /<Style[^>]*TargetType="(?:\{x:Type )?([\w.]+)"?/) { $target = $1 }
    if (!$style_bg && $ln =~ /<Setter\s+Property="Background"\s+Value="([^"]+)"/) { $style_bg = $1 }
    next unless $ln =~ /^(\s*)<Setter\s+Property="(Background|BorderBrush|Foreground)"\s+Value="([^"]+)"(\/?>)(.*)$/;
    my ($ind, $p, $v, $end, $tail) = ($1, $2, $3, $4, $5);
    next if $tail =~ /TargetName/;
    my $new;
    if ($p eq 'Background') {
        $new = klass($v, @$btn_blue) ? 'GlassButtonPrimary'
             : klass($v, @$near_white) ? ($field_el{$target} ? 'GlassField' : 'GlassSurfaceSoft')
             : klass($v, @$blue_chip) ? 'GlassChip'
             : klass($v, @$gray_fill) ? 'GlassDivider' : undef;
    } elsif ($p eq 'BorderBrush') {
        $new = klass($v, @$gray_border) ? 'GlassSurfaceBorder'
             : klass($v, @$blue_border) ? 'GlassAccentBorder' : undef;
    } else {
        $new = klass($v, @$dark_text) ? 'GlassTextPrimary'
             : klass($v, @$mid_text) ? 'GlassTextSecondary'
             : klass($v, @$blue_text) ? 'GlassAccentText' : undef;
        # 按钮底是实体色时不要动文字，只有底色本身也变成玻璃面时才跟着换
        if ($btn_fam{$target} && defined $new) {
            my $bg_glassy = $style_bg eq '' || $style_bg =~ /DynamicResource Glass(Sub|Field|Surf|Div)/
                         || klass($style_bg, @$near_white);
            $new = undef unless $bg_glassy;
        }
    }
    next unless defined $new;
    push @report, sprintf('%5d %-14s %-12s %s -> %s', $i + 1, $target || '?', "$p", $v, $new);
    $lines[$i] = qq{$ind<Setter Property="$p" Value="{DynamicResource $new}"$end$tail} if $apply;
}
print STDERR "$_\n" for @report;
print STDERR 'TOTAL ' . scalar(@report) . "\n";
print join("\n", @lines) if $apply;
