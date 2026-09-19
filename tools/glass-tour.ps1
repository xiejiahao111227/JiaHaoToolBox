param([string]$Exe, [string]$OutDir)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @"
using System;using System.Runtime.InteropServices;
public struct RG{public int L;public int T;public int R;public int B;}
public class PG{
 [DllImport("user32.dll")]public static extern bool GetWindowRect(IntPtr h,out RG r);
 [DllImport("user32.dll")]public static extern bool PrintWindow(IntPtr h,IntPtr hdc,uint f);
 [DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")]public static extern bool ShowWindow(IntPtr h,int c);
 [DllImport("user32.dll")]public static extern IntPtr SendMessage(IntPtr h,uint msg,IntPtr w,IntPtr l);
 [DllImport("user32.dll")]public static extern bool ScreenToClient(IntPtr h,ref RG p);
 [DllImport("user32.dll")]public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")]public static extern void mouse_event(uint f,uint d,uint e,IntPtr x);
 [DllImport("user32.dll")]public static extern bool GetCursorPos(out PT p);
 public struct PT{public int X;public int Y;}
}
"@
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
function Say([string]$m) { [Console]::Out.WriteLine($m) }
$AU = [System.Windows.Automation.AutomationElement]
$root = $AU::RootElement

# 主题用偏好文件预设（顺带验证启动恢复逻辑）；UIA Invoke 主题按钮会连发两次 Click，不可靠
$pref = Join-Path $env:LOCALAPPDATA 'JiaHaoTool\theme.txt'
if ($StartDark) {
    if (-not (Test-Path (Split-Path $pref))) { New-Item -ItemType Directory -Path (Split-Path $pref) -Force | Out-Null }
    Set-Content -Path $pref -Value 'Dark' -NoNewline
} elseif (Test-Path $pref) {
    Remove-Item $pref -Force
}

$p = Start-Process -FilePath $Exe -PassThru
$deadline = (Get-Date).AddSeconds(60); $hwnd = [IntPtr]::Zero
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 700; $p.Refresh()
    if ($p.HasExited) { Write-Output 'APP-EXITED-EARLY'; exit 1 }
    if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $hwnd = $p.MainWindowHandle; break }
}
if ($hwnd -eq [IntPtr]::Zero) { Write-Output 'NO-WINDOW'; Stop-Process -Id $p.Id -Force; exit 1 }
Start-Sleep -Seconds 6
$cursorHome = New-Object PG+PT
[void][PG]::GetCursorPos([ref]$cursorHome)

function Save-Shot([string]$png) {
    $w = 0; $h = 0
    for ($i = 0; $i -lt 12; $i++) {
        [void][PG]::ShowWindow($hwnd, 9)
        [void][PG]::SetForegroundWindow($hwnd)
        Start-Sleep -Milliseconds 500
        $r = New-Object RG; [void][PG]::GetWindowRect($hwnd, [ref]$r)
        $w = $r.R - $r.L; $h = $r.B - $r.T
        if ($w -ge 400 -and $h -ge 400) { break }
    }
    if ($w -lt 400 -or $h -lt 400) { Write-Output "BAD-RECT $png ($w x $h)"; return }
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc(); [void][PG]::PrintWindow($hwnd, $hdc, 2); $g.ReleaseHdc($hdc); $g.Dispose()
    $bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    Write-Output ("shot {0} ({1}x{2})" -f (Split-Path $png -Leaf), $w, $h)
}

$cond = New-Object System.Windows.Automation.PropertyCondition($AU::ProcessIdProperty, $p.Id)
$kidsDump = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
for ($i = 0; $i -lt $kidsDump.Count; $i++) {
    $k = $kidsDump.Item($i).Current
    Say ("TOP[$i] class='$($k.ClassName)' hwnd=$($k.NativeWindowHandle) name='$($k.Name)'")
}
Say ("MAIN hwnd=$($hwnd.ToInt64())")
function Get-Window {
    # 桌面上可能挂着别的同进程顶层窗口（输入法/安全控件的浮层），只认标题为嘉豪工具箱的那个
    $kids = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
    for ($i = 0; $i -lt $kids.Count; $i++) {
        $k = $kids.Item($i)
        if ($k.Current.ClassName -eq 'Window') { return $k }
    }
    return $null
}
function Find-ById([string]$id, [int]$tries = 1) {
    for ($k = 0; $k -lt $tries; $k++) {
        $w = Get-Window
        if ($w) {
            $c = New-Object System.Windows.Automation.PropertyCondition($AU::AutomationIdProperty, $id)
            $e = $w.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $c)
            if ($e) { return $e }
        }
        Start-Sleep -Milliseconds 600
    }
    return $null
}
function Find-ByName([string]$name, [int]$tries = 1) {
    for ($k = 0; $k -lt $tries; $k++) {
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

function Say([string]$m) { [Console]::Out.WriteLine($m) }
function Theme-State {
    # theme.txt 只有点过主题按钮才会写；没有文件就是浅色
    $f = Join-Path $env:LOCALAPPDATA 'JiaHaoTool\theme.txt'
    if (Test-Path $f) { return (Get-Content $f -Raw).Trim() } else { return 'Light(默认)' }
}
function Element-Count {
    $w = Get-Window
    if (-not $w) { return -1 }
    return $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition).Count
}

# SideMenuItem 没有自动化面板，只能点它的标题文字。实测 WPF 只认真实硬件输入：
# SendMessage/PostMessage 投递的 WM_LBUTTONDOWN 能改 hover 却触发不了 Click，所以这里用 SetCursorPos + mouse_event。
function Click-At([int]$x, [int]$y) {
    [void][PG]::SetCursorPos($x, $y)
    Start-Sleep -Milliseconds 220
    [void][PG]::mouse_event(0x0002, 0, 0, [IntPtr]::Zero)   # LEFTDOWN
    Start-Sleep -Milliseconds 90
    [void][PG]::mouse_event(0x0004, 0, 0, [IntPtr]::Zero)   # LEFTUP
    Start-Sleep -Milliseconds 1200
}
function Nav-To([string]$label, [string]$view) {
    $el = Find-ByName $label 6
    if (-not $el) { Say "MISS $label"; return }
    $r = $el.Current.BoundingRectangle
    $x = [int]($r.Left + $r.Width / 2); $y = [int]($r.Top + $r.Height / 2)
    $before = Element-Count
    for ($try = 0; $try -lt 3; $try++) {
        [void][PG]::SetForegroundWindow($hwnd)
        Start-Sleep -Milliseconds 250
        Click-At ($x - 14) ($y - $try * 3)
        if ((Element-Count) -ne $before) { break }
    }
    Say ("NAV {0} -> {1} ({2},{3}) 元素数 {4} 主题 {5}" -f $label, $view, $x, $y, (Element-Count), (Theme-State))
}

# 导航标题 -> 页面名（SideMenuItem 不进 UIA 树，只能按标题文字定位）
$tour = [ordered]@{
    '主页'     = 'Home'
    '投屏'     = 'ScreenMirror'
    '基本刷入' = 'BasicFlash'
    '可视刷写' = 'FastbootVis'
    '模块专区' = 'HiddenEnv'
    '欧加线刷' = 'OujiaFlash'
    'EDL刷写'  = 'EdlFlash'
    '降级助手' = 'ColorOS'
    '应用管理' = 'AppManager'
    'Payload'  = 'Payload'
    '下载专区' = 'Download'
    '关于'     = 'About'
}
$prefix = if ($Theme) { "$Theme-" } else { '' }
foreach ($k in $tour.Keys) {
    if ($Only -and (@($Only -split ',') -notcontains $tour[$k])) { continue }
    Nav-To $k $tour[$k]
    Save-Shot (Join-Path $OutDir ("{0}{1}.png" -f $prefix, $tour[$k]))
}
Write-Output 'done'
if ($null -ne $cursorHome) { [void][PG]::SetCursorPos($cursorHome.X, $cursorHome.Y) }   # 把指针还给用户
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
