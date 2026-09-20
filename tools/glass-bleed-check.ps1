param([string]$Exe, [string]$OutDir)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @"
using System;using System.Runtime.InteropServices;
public struct RG3{public int L;public int T;public int R;public int B;}
public class PG3{
 [DllImport("user32.dll")]public static extern bool GetWindowRect(IntPtr h,out RG3 r);
 [DllImport("user32.dll")]public static extern bool PrintWindow(IntPtr h,IntPtr hdc,uint f);
 [DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")]public static extern bool ShowWindow(IntPtr h,int c);
 [DllImport("user32.dll")]public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")]public static extern void mouse_event(uint f,uint d,uint e,IntPtr x);
 [DllImport("user32.dll")]public static extern bool GetCursorPos(out PT3 p);
 public struct PT3{public int X;public int Y;}
}
"@
function Say([string]$text) { [Console]::Out.WriteLine($text) }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

# 动效全关：光斑不漂、没有入场淡入，两张「工具设置」截图才允许逐像素比
$prefDir = Join-Path $env:LOCALAPPDATA 'JiaHaoTool'
$pref = Join-Path $prefDir 'settings.txt'
if (-not (Test-Path $prefDir)) { New-Item -ItemType Directory -Path $prefDir -Force | Out-Null }
Set-Content -Path $pref -Value "theme=Light`r`nmotion=0" -Encoding UTF8 -NoNewline

$p = Start-Process -FilePath $Exe -PassThru
$deadline = (Get-Date).AddSeconds(60); $hwnd = [IntPtr]::Zero
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 700; $p.Refresh()
    if ($p.HasExited) { Say 'APP-EXITED-EARLY'; exit 1 }
    if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $hwnd = $p.MainWindowHandle; break }
}
if ($hwnd -eq [IntPtr]::Zero) { Say 'NO-WINDOW'; Stop-Process -Id $p.Id -Force; exit 1 }
Start-Sleep -Seconds 6
$cursorHome = New-Object PG3+PT3
[void][PG3]::GetCursorPos([ref]$cursorHome)

$AU = [System.Windows.Automation.AutomationElement]
$root = $AU::RootElement
$cond = New-Object System.Windows.Automation.PropertyCondition($AU::ProcessIdProperty, $p.Id)
function Get-Window {
    $kids = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
    for ($i = 0; $i -lt $kids.Count; $i++) {
        if ($kids.Item($i).Current.ClassName -eq 'Window') { return $kids.Item($i) }
    }
    return $null
}
function Find-ByName([string]$name) {
    for ($k = 0; $k -lt 8; $k++) {
        $w = Get-Window
        if ($w) {
            $c = New-Object System.Windows.Automation.PropertyCondition($AU::NameProperty, $name)
            $e = $w.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $c)
            if ($e) { return $e }
        }
        Start-Sleep -Milliseconds 600
    }
    return $null
}
function Element-Count {
    $w = Get-Window
    if (-not $w) { return -1 }
    return $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition).Count
}
function Click-At([int]$x, [int]$y) {
    [void][PG3]::SetCursorPos($x, $y)
    Start-Sleep -Milliseconds 220
    [void][PG3]::mouse_event(0x0002, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 90
    [void][PG3]::mouse_event(0x0004, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 1200
}
function Nav-To([string]$label) {
    $el = Find-ByName $label
    if (-not $el) { Say "MISS $label"; return $false }
    $r = $el.Current.BoundingRectangle
    $x = [int]($r.Left + $r.Width / 2); $y = [int]($r.Top + $r.Height / 2)
    $before = Element-Count
    for ($try = 0; $try -lt 3; $try++) {
        [void][PG3]::SetForegroundWindow($hwnd)
        Start-Sleep -Milliseconds 250
        Click-At ($x - 14) ($y - $try * 3)
        if ((Element-Count) -ne $before) { break }
    }
    Say ("NAV {0} 元素数 {1}" -f $label, (Element-Count))
    return $true
}
function Grab([string]$png) {
    for ($i = 0; $i -lt 12; $i++) {
        [void][PG3]::ShowWindow($hwnd, 9)
        [void][PG3]::SetForegroundWindow($hwnd)
        Start-Sleep -Milliseconds 500
        $r = New-Object RG3; [void][PG3]::GetWindowRect($hwnd, [ref]$r)
        $script:ww = $r.R - $r.L; $script:hh = $r.B - $r.T
        if ($ww -ge 400 -and $hh -ge 400) { break }
    }
    $bmp = New-Object System.Drawing.Bitmap($ww, $hh)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc(); [void][PG3]::PrintWindow($hwnd, $hdc, 2); $g.ReleaseHdc($hdc); $g.Dispose()
    $bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
    Say ("shot {0} ({1}x{2})" -f (Split-Path $png -Leaf), $ww, $hh)
    return $bmp
}

# 疑犯是 Rom专区（RomDownloadview，唯一没挂 GlassPageStyle 的页面）：
# 从它跳进设置页后截图，再和「主页 → 设置页」的干净截图逐点比，有差异就是上一页穿透进来了。
[void](Nav-To '下载专区')
$romOk = Nav-To 'Rom专区'
[void](Nav-To '工具设置')
$s1 = Grab (Join-Path $OutDir 'bleed-1-settings-after-rom.png')

[void](Nav-To '主页')
[void](Nav-To '工具设置')
$s2 = Grab (Join-Path $OutDir 'bleed-2-settings-clean.png')

$diff = 0
for ($y = 0; $y -lt $hh; $y += 2) {
    for ($x = 0; $x -lt $ww; $x += 2) {
        $c1 = $s1.GetPixel($x, $y); $c2 = $s2.GetPixel($x, $y)
        if ([Math]::Abs($c1.R - $c2.R) + [Math]::Abs($c1.G - $c2.G) + [Math]::Abs($c1.B - $c2.B) -gt 6) { $diff++ }
    }
}
$s1.Dispose(); $s2.Dispose()
Say ("Rom专区绕行 vs 主页直达：明显差异点 $diff")
if (-not $romOk) { Say 'SKIP Rom专区 未定位到，未验证穿透' }
if ($diff -eq 0) { Say 'OK 设置页干净，无上一级页面残留' } else { Say "FAIL 设置页有 $diff 个差异点，疑似残留" }
Say 'done'
[void][PG3]::SetCursorPos($cursorHome.X, $cursorHome.Y)
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
