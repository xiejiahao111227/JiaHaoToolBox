param([string]$Exe)
# 底栏状态灯巡检：启动后反复采样指示灯区域，证明「设备检测开着且未连接」时灯亮且在呼吸
# （同一盏灯的绿色像素数/均值亮度在多个档位之间起伏），并把窗口尺寸打印出来方便核对坐标。
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;using System.Runtime.InteropServices;
public struct RG2{public int L;public int T;public int R;public int B;}
public class PG2{
 [DllImport("user32.dll")]public static extern bool GetWindowRect(IntPtr h,out RG2 r);
 [DllImport("user32.dll")]public static extern bool PrintWindow(IntPtr h,IntPtr hdc,uint f);
 [DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr h);
}
"@
function Say([string]$line) { [Console]::Out.WriteLine($line) }
$prefDir = Join-Path $env:LOCALAPPDATA 'JiaHaoTool'
$pref = Join-Path $prefDir 'settings.txt'
if (-not (Test-Path $prefDir)) { New-Item -ItemType Directory -Path $prefDir -Force | Out-Null }
Set-Content -Path $pref -Value "theme=Light`r`nmotion=1" -Encoding UTF8 -NoNewline

$p = Start-Process -FilePath $Exe -PassThru
$deadline = (Get-Date).AddSeconds(60); $script:hwnd = [IntPtr]::Zero
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500; $p.Refresh()
    if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $script:hwnd = $p.MainWindowHandle; break }
}
function Rect {
    $script:rr = New-Object RG2
    [void][PG2]::GetWindowRect($script:hwnd, [ref]$script:rr)
}
Rect
Say ("窗口 $($script:rr.L),$($script:rr.T) -> $($script:rr.R),$($script:rr.B)")
function Grab {
    Rect
    $w = $script:rr.R - $script:rr.L
    $h = $script:rr.B - $script:rr.T
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc(); [void][PG2]::PrintWindow($script:hwnd, $hdc, 2); $g.ReleaseHdc($hdc); $g.Dispose()
    return $bmp
}
# 指示灯在底栏 Margin=466 处、8x8、垂直居中；取它周围一小块。
# 检测中是琥珀色 (255,183,77)，连上是绿色 (125,255,159)，两种都要单独数，别只认绿色。
function Lamp-Stat($bmp) {
    $amber = 0; $green = 0; $maxB = 0; $sumB = 0
    for ($y = 766; $y -lt 792; $y++) {
        for ($x = 458; $x -lt 484; $x++) {
            $c = $bmp.GetPixel($x, $y)
            $isAmber = $c.R -gt 150 -and $c.R -gt $c.B + 60 -and $c.G -gt $c.B
            $isGreen = $c.G -gt 150 -and $c.G -gt $c.R + 20 -and $c.G -gt $c.B + 20
            if ($isAmber -or $isGreen) {
                if ($isAmber) { $amber++ } else { $green++ }
                $b = $c.R + $c.G + $c.B
                $sumB += $b; if ($b -gt $maxB) { $maxB = $b }
            }
        }
    }
    $n = $amber + $green
    return @($n, $amber, $green, $maxB, $(if ($n) { [int]($sumB / $n) } else { 0 }))
}
[void][PG2]::SetForegroundWindow($script:hwnd)
$t0 = Get-Date
$samples = @()
for ($i = 0; $i -lt 16; $i++) {
    $bmp = Grab
    $s = Lamp-Stat $bmp
    $samples += , @([int]((Get-Date) - $t0).TotalMilliseconds, $s[0], $s[1], $s[2], $s[3], $s[4])
    Say ("t={0,5}ms 灯像素 {1,3} (琥珀 {2,3}/绿 {3,3}) 峰值 {4,5} 均值 {5,5}" -f $samples[-1][0], $s[0], $s[1], $s[2], $s[3], $s[4])
    $bmp.Dispose()
    Start-Sleep -Milliseconds 450
}
$lit = @($samples | Where-Object { $_[1] -gt 0 })
$levels = @($lit | ForEach-Object { $_[5] } | Sort-Object -Unique)
Say ("亮灯采样 {0}/{1} 次，均值亮度 {2} 档：{3}" -f $lit.Count, $samples.Count, $levels.Count, ($levels -join '/'))
if ($lit.Count -ge 3 -and $levels.Count -ge 3) { Say 'OK 灯亮且在呼吸' }
elseif ($lit.Count -ge 3) { Say 'FAIL 灯亮但亮度恒定，没呼吸' }
else { Say 'FAIL 没拍到亮灯' }
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
