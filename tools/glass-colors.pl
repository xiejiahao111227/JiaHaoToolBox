#!/usr/bin/perl
# 元素感知的配色扫描：只改元素特性上的写死颜色，不动 Style/Setter（那里的蓝色渐变按钮是刻意保留的实体胶囊）。
# 输出替换清单到 STDERR，替换后的 XAML 到 STDOUT。
use strict;
use warnings;
require './tools/glass-palette.pl';
my ($pal_near_white, $pal_blue_chip, $pal_gray_fill, $pal_btn_blue, $pal_gray_border,
    $pal_blue_border, $pal_dark_text, $pal_mid_text, $pal_blue_text) = glass_palette();
my @near_white  = @$pal_near_white;
my @blue_chip   = @$pal_blue_chip;
my @gray_fill   = @$pal_gray_fill;
my @btn_blue    = @$pal_btn_blue;
my @gray_border = @$pal_gray_border;
my @blue_border = @$pal_blue_border;
my @dark_text   = @$pal_dark_text;
my @mid_text    = @$pal_mid_text;
my @blue_text   = @$pal_blue_text;


my %field_el = map { $_ => 1 } qw(TextBox ComboBox PasswordBox);
my %skip_btn = map { $_ => 1 } qw(Button ToggleButton RepeatButton RadioButton CheckBox Thumb ScrollBar Slider Window Page Expander);
my %btn_fam  = map { $_ => 1 } qw(Button ToggleButton RepeatButton RadioButton CheckBox);

sub klass { my ($v, @list) = @_; for (@list) { return 1 if lc($_) eq lc($v) } return 0 }

my @report;
local $/;
my $xaml = <>;
my $count = ($xaml =~ s{<([A-Za-z][\w.]*)([^<>]*)>}{
    my ($tag, $attrs) = ($1, $2);
    '<' . $tag . tune($tag, $attrs) . '>';
}gse);
print STDERR "tags scanned: $count\n";
print STDERR "$_\n" for @report;
print STDERR "TOTAL " . scalar(@report) . "\n";
print $xaml;

sub tune {
    my ($tag, $attrs) = @_;
    return $attrs if $tag eq 'Setter';
    my %has;
    my $copy = $attrs;
    $has{$1} = $2 while $copy =~ /\b(Background|BorderBrush|Foreground)="([^"]*)"/g;
    my $bg_locked = 0;
    if (defined $has{Background}) {
        my $b = $has{Background};
        $bg_locked = !(klass($b, @near_white) || klass($b, @blue_chip) || klass($b, @gray_fill)
                       || $b eq 'Transparent' || $b =~ /DynamicResource Glass/);
    }
    # 淡蓝实心按钮统一升级成主色按钮，按钮内的文字随后要跟着换成反白色
    my $btn_filled = $btn_fam{$tag} && klass($has{Background} // '', @btn_blue);
    $attrs =~ s{\b(Background|BorderBrush|Foreground)="([^"]*)"}{
        my ($p, $v) = ($1, $2);
        my $new;
        if ($p eq 'Background') {
            if ($btn_fam{$tag}) {
                $new = klass($v, @btn_blue)   ? 'GlassButtonPrimary'
                     : klass($v, @near_white) ? 'GlassSurfaceSoft' : undef;
            } else {
                $new = klass($v, @near_white) ? ($field_el{$tag} ? 'GlassField' : 'GlassSurfaceSoft')
                     : klass($v, @blue_chip)  ? 'GlassChip'
                     : klass($v, @gray_fill)  ? 'GlassDivider' : undef;
            }
        } elsif ($p eq 'BorderBrush') {
            $new = $btn_filled && klass($v, @blue_border) ? 'GlassButtonPrimary'
                 : klass($v, @gray_border) ? 'GlassSurfaceBorder'
                 : klass($v, @blue_border) ? 'GlassAccentBorder' : undef;
        } else {
            if ($btn_filled) {
                $new = 'GlassOnAccent';
            } elsif (!$bg_locked) {
                $new = klass($v, @dark_text) ? 'GlassTextPrimary'
                     : klass($v, @mid_text)  ? 'GlassTextSecondary'
                     : klass($v, @blue_text) ? 'GlassAccentText' : undef;
            }
        }
        if (defined $new) {
            push @report, "$tag.$p $v -> $new";
            "$p=\"{DynamicResource $new}\"";
        } else { "$p=\"$v\"" }
    }gse;
    $attrs;
}
