#!/usr/bin/perl
# 把列表/表格/按钮里残留的浅色硬编码换成玻璃语义画刷，深色主题下才不会白底压白字。
use strict;
use warnings;

my $file = 'JiaHaoToolBox/MainWindow.xaml';
my $apply = grep { $_ eq '--apply' } @ARGV;

my %bg = (
    '#FFF1F7FD' => 'GlassRowHover',
    '#FFF1F9FF' => 'GlassRowHover',
    '#FFF0F8FC' => 'GlassRowHover',
    '#FFFBFCFD' => 'GlassRowAlt',
    '#FFFAFCFE' => 'GlassRowAlt',
    '#FFE2F2FE' => 'GlassSelection',
    '#FF87CEEB' => 'GlassSelection',
    '#FFF2F6F9' => 'GlassHeader',
    '#FFF8FAFC' => 'GlassHeader',
    '#FFE3EEFA' => 'GlassHeader',
    '#FFD7EAFF' => 'GlassChip',
    '#FFECF5FF' => 'GlassChip',
    '#FFD8DDE3' => 'GlassDisabled',
    '#FFF1F3F5' => 'GlassDisabled',
    '#FF63BFF4' => 'GlassButtonPrimary',
    '#FF4AAFE9' => 'GlassButtonPrimaryHover',
);
my %border = (
    '#FF6BBFE3' => 'GlassAccentBorder',
    '#FFBFD7F3' => 'GlassAccentBorder',
    '#FF9BCDEE' => 'GlassAccentBorder',
    '#FF8BD5FF' => 'GlassAccentBorder',
    '#FFD6E4F5' => 'GlassAccentBorder',
    '#FF4A90E2' => 'GlassAccentBorder',
    '#FFF0F1F5' => 'GlassSurfaceBorder',
    '#FFE2E8F0' => 'GlassSurfaceBorder',
    '#FFE1E6EC' => 'GlassSurfaceBorder',
    '#FFEAEEF2' => 'GlassSurfaceBorder',
    '#FFE9EDF2' => 'GlassSurfaceBorder',
    '#FFDDE3E8' => 'GlassSurfaceBorder',
);
my %fg = (
    '#FF8A949E' => 'GlassTextSecondary',
    '#FF7A8793' => 'GlassTextSecondary',
);

my $bg_re = join '|', map { quotemeta } keys %bg;
my $bd_re = join '|', map { quotemeta } keys %border;
my $fg_re = join '|', map { quotemeta } keys %fg;

open my $in, '<', $file or die "$file: $!";
my @lines = <$in>;
close $in;

my %hits;
sub note { $hits{$_[0]}++ }
for my $l (@lines) {
    my $orig = $l;
    $l =~ s{(Property="Background"\s+Value="|Background="|AlternatingRowBackground=")($bg_re|SkyBlue)}
           { note($2); $1 . ( $2 eq 'SkyBlue' ? '{DynamicResource GlassButtonPrimary}' : '{DynamicResource ' . $bg{$2} . '}' ) }ge;
    $l =~ s{(Property="BorderBrush"\s+Value="|BorderBrush=")($bd_re)}
           { note($2); $1 . '{DynamicResource ' . $border{$2} . '}' }ge;
    $l =~ s{(Property="Foreground"\s+Value="|Foreground=")($fg_re)}
           { note($2); $1 . '{DynamicResource ' . $fg{$2} . '}' }ge;
}
for my $k (sort keys %hits) { printf "%-12s x%d\n", $k, $hits{$k}; }
if ($apply) {
    open my $out, '>', $file or die;
    print $out @lines;
    close $out;
    print "applied\n";
} else {
    print "dry-run only\n";
}
