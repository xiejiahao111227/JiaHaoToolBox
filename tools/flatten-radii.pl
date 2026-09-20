use strict;
use warnings;

# 把 MainWindow.xaml / Window1.xaml 里写死的圆角字面量换成 {DynamicResource GlassRadiusN}，
# 让全站只有一处圆角来源（Theme/Glass.Radius.xaml），改数值不必再逐页翻 XAML。
# 0 本来就是直角，正则里直接不匹配；出现刻度表里没有的数值则报错退出，避免留下哑键。
# 替换串一律走下面的小函数拼字符串，别在 s!!! 里手写 XAML 引号，容易多打一个撇号。

my @tokens = (3,4,5,6,7,8,9,10,11,12,14,16,21);
my %ok = map { $_ => 1 } @tokens;

sub key {
    my ($v) = @_;
    return 'GlassRadius' . $v if $ok{$v};
    die "刻度表里没有 CornerRadius=$v，先加进 Theme/Glass.Radius.xaml 再跑\n";
}

sub dyn { return '"{DynamicResource ' . key($_[0]) . '}"' }
sub setter {
    my ($prop, $v) = @_;
    return '<Setter Property="' . $prop . '" Value=' . dyn($v) . '/>';
}

sub convert {
    my ($path) = @_;
    open my $in, '<', $path or die "读不到 $path: $!";
    local $/;
    my $text = <$in>;
    close $in;

    # 1) Setter 形式
    my $sa = $text =~ s!<Setter Property="hc:BorderElement\.CornerRadius" Value="([1-9]\d*)"/>! setter('hc:BorderElement.CornerRadius', $1) !ge;
    my $sp = $text =~ s!<Setter Property="CornerRadius" Value="([1-9]\d*)"/>! setter('CornerRadius', $1) !ge;
    # 2) 附加属性形式 hc:BorderElement.CornerRadius="10"
    my $at = $text =~ s!hc:BorderElement\.CornerRadius="([1-9]\d*)"! 'hc:BorderElement.CornerRadius=' . dyn($1) !ge;
    # 3) 半胶囊 CornerRadius="0,10,10,0"
    my $hf = $text =~ s!CornerRadius="0,10,10,0"!CornerRadius="{DynamicResource GlassRadiusLeft10}"!g;
    # 4) 其余 Border.CornerRadius="N"（分隔符换成 #，因为反向断言 (?<! 里带感叹号，会跟 s!!! 撞掉）
    my $pl = $text =~ s#(?<![:.\w])CornerRadius="([1-9]\d*)"# 'CornerRadius=' . dyn($1) #ge;

    open my $out, '>', $path or die "写不进 $path: $!";
    print $out $text;
    close $out;
    my $left = () = $text =~ /(?<![:.\w])CornerRadius="\d"/g;
    printf "%s: attached=%s setter_attached=%s setter_plain=%s plain=%s half=%s 残留=%s\n",
        $path, $at // 0, $sa // 0, $sp // 0, $pl // 0, $hf // 0, $left // 0;
}

convert($_) for @ARGV;
