#!/usr/bin/perl
use strict; use warnings;
my $f = 'MainWindow.xaml';
open(my $in, '<:raw', $f) or die "open: $!";
local $/; my $t = <$in>; close $in;
my @log;

# 1) Border 卡片样式统一 BasedOn GlassCardStyle，只留各自的圆角与内边距
my %cards = (
    HomeCardStyle       => [18, 16],
    AutorootCardStyle   => [16, 12],
    BasicFlashCardStyle => [16, 12],
    VioletCardStyle     => [16, 14],
    ColorOSCardStyle    => [16, 14],
    AboutCardStyle      => [16, 16],
);
for my $k (sort keys %cards) {
    my ($r, $p) = @{ $cards{$k} };
    my $n = ($t =~ s{<Style\s+([^>]*?)x:Key="\Q$k\E"([^>]*?)TargetType="Border">(.*?)</Style>}
        {<Style x:Key="$k" TargetType="Border" BasedOn="{StaticResource GlassCardStyle}">\n                                <Setter Property="CornerRadius" Value="$r"/>\n                                <Setter Property="Padding" Value="$p"/>\n                                </Style>}gs);
    push @log, "$k Border 卡片: $n";
}

# 2) GroupBox 卡片：去掉自带的浅色 Background/BorderBrush/Foreground，改由 PayloadGroupBoxStyle 的玻璃面提供
my @gb = qw(FastbootCardGroupBoxStyle EdlCardGroupBoxStyle OugaFlashCardGroupBoxStyle ColorOSLogGroupBoxStyle);
for my $k (@gb) {
    my $done = 0;
    $t =~ s{(<Style\s+[^>]*x:Key="\Q$k\E"[^>]*>)(.*?)(</Style>)}{
        my ($head, $body, $tail) = ($1, $2, $3);
        my $before = length $body;
        $body =~ s{<Setter\s+Property="Background"[^>]*/>}{}g;
        $body =~ s{<Setter\s+Property="BorderBrush"[^>]*/>}{}g;
        $body =~ s{<Setter\s+Property="Foreground"[^>]*/>}{}g;
        $body =~ s{<Setter\s+Property="hc:BorderElement\.CornerRadius"[^>]*/>}{}g;
        $body =~ s{(\n(\s*)<Setter\s+Property="BorderThickness")}{\n$2<Setter Property="hc:BorderElement.CornerRadius" Value="16"$1}g if $body =~ /BorderThickness/;
        $done = $before != length $body ? 1 : 0;
        "$head$body$tail";
    }gse;
    push @log, "$k GroupBox 卡片: " . ($done ? 'ok' : 'skip');
}

open(my $out, '>:raw', $f) or die "write: $!";
print $out $t; close $out;
print "$_\n" for @log;
