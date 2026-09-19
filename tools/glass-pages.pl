#!/usr/bin/perl
# 把全部页面根 Grid 换成统一的玻璃页面样式：去掉各自写死的 Background，套用 GlassPageStyle。
use strict;
use warnings;

my @views = qw(
    HomeView AutorootView ScreenMirrorView BasicFlashView FastbootVisualizationView
    HiddenEnvironmentView VioletDownloadView SystemZoneView DownloadView
    PayloadView EdlFlashView ColorOSAssistantView
    BackupAssistantView AboutToolView AppManagementView AndroidGeneralView OujiaFlashView
);

local $/;
my $xaml = <>;
my $hit = 0;
for my $v (@views) {
    $hit += ($xaml =~ s{(<Grid\s+(?:[^<>]*?)Name="$v"[^<>]*?>)}{
        my $tag = $1;
        my $t = $tag =~ s/\s+Background="[^"]*"//g;
        $tag =~ s/(Name="$v")/$1 Style="{StaticResource GlassPageStyle}"/;
        $tag;
    }gse);
}
print STDERR "no-match: $_\n" for grep { my $n = $_; !($xaml =~ /Name="$n"[^<>]*Style="\{StaticResource GlassPageStyle\}"/s) } @views;
print $xaml;
