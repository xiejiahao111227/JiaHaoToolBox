param([string]$Exe, [string]$OutDir)
# 工具设置页的交互巡检：真的点开关/单选，验证外观当场切换 + 偏好落盘 + 重启后恢复。
# 第 1 行必须是 param——ps-enc.sh 会丢掉首行，参数由前置赋值语句给出。
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
 [DllImport("user32.dll")]public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")]public static extern void mouse_event(uint f,uint d,uint e,IntPtr x);
 [DllImport("user32.dll")]public static extern bool GetCursorPos(out PT p);
 [DllImport("user32.dll")]public static extern void keybd_event(byte vk,byte scan,uint flags,IntPtr extra);
 [DllImport("user32.dll")]public static extern bool BringWindowToTop(IntPtr h);
 [DllImport("user32.dll")]public static extern IntPtr SetActiveWindow(IntPtr h);
 [DllImport("user32.dll")]public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")]public static extern int GetWindowThreadProcessId(IntPtr h,out int pid);
 [DllImport("user32.dll")]public static extern bool AttachThreadInput(uint a,uint b,bool f);
 [DllImport("kernel32.dll")]public static extern uint GetCurrentThreadId();
 [DllImport("user32.dll")]public static extern IntPtr WindowFromPoint(PT p);
 [DllImport("user32.dll")]public static extern IntPtr GetAncestor(IntPtr h,uint flags);
 public struct PT{public int X;public int Y;}
}
"@
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
function Say([string]$line) { [Console]::Out.WriteLine($line) }
$AU = [System.Windows.Automation.AutomationElement]
$root = $AU::RootElement
$prefDir = Join-Path $env:LOCALAPPDATA 'JiaHaoTool'
$pref = Join-Path $prefDir 'settings.txt'
if (-not (Test-Path $prefDir)) { New-Item -ItemType Directory -Path $prefDir -Force | Out-Null }
if ($Preset) { Set-Content -Path $pref -Value ($Preset -split ';' -join "`r`n") -Encoding UTF8 -NoNewline }
function Pref-Dump([string]$tag) {
    if (-not (Test-Path $pref)) { Say "PREF[$tag] <无文件>"; return }
    Say ("PREF[{0}] {1}" -f $tag, (((Get-Content $pref) | Where-Object { $_ } | ForEach-Object { $_.Trim() }) -join ' '))
}
Pref-Dump '启动前'

$p = Start-Process -FilePath $Exe -PassThru
$deadline = (Get-Date).AddSeconds(60); $hwnd = [IntPtr]::Zero
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 700; $p.Refresh()
    if ($p.HasExited) { Say 'APP-EXITED-EARLY'; exit 1 }
    if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $hwnd = $p.MainWindowHandle; break }
}
if ($hwnd -eq [IntPtr]::Zero) { Say 'NO-WINDOW'; Stop-Process -Id $p.Id -Force; exit 1 }
Start-Sleep -Seconds 6
$cursorHome = New-Object PG+PT
[void][PG]::GetCursorPos([ref]$cursorHome)
$cond = New-Object System.Windows.Automation.PropertyCondition($AU::ProcessIdProperty, $p.Id)
function Get-Window {
    $kids = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
    for ($i = 0; $i -lt $kids.Count; $i++) { if ($kids.Item($i).Current.ClassName -eq 'Window') { return $kids.Item($i) } }
    return $null
}
function Find-El([string]$by, [string]$value, [int]$tries = 6) {
    for ($k = 0; $k -lt $tries; $k++) {
        $w = Get-Window
        if ($w) {
            $prop = if ($by -eq 'id') { $AU::AutomationIdProperty } else { $AU::NameProperty }
            # 同名元素会有俩：左栏 SideMenuItem 的标题文字，和此刻被 Collapsed 掉的顶部标签按钮
            # （矩形在 -32000 附近）。FindFirst 先撞上后者就点了个寂寞，所以只挑不在屏幕外的。
            $all = $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition($prop, $value)))
            for ($i = 0; $i -lt $all.Count; $i++) {
                if (-not $all.Item($i).Current.IsOffscreen) { return $all.Item($i) }
            }
        }
        Start-Sleep -Milliseconds 600
    }
    return $null
}
function Save-Shot([string]$png) {
    $w = 0; $h = 0
    for ($i = 0; $i -lt 12; $i++) {
        [void][PG]::ShowWindow($hwnd, 9); [void][PG]::SetForegroundWindow($hwnd)
        Start-Sleep -Milliseconds 500
        $r = New-Object RG; [void][PG]::GetWindowRect($hwnd, [ref]$r)
        $w = $r.R - $r.L; $h = $r.B - $r.T
        if ($w -ge 400 -and $h -ge 400) { break }
    }
    if ($w -lt 400 -or $h -lt 400) { Say "BAD-RECT $png"; return }
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc(); [void][PG]::PrintWindow($hwnd, $hdc, 2); $g.ReleaseHdc($hdc); $g.Dispose()
    $bmp.Save((Join-Path $OutDir $png), [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    Say ("shot {0}" -f $png)
}
# WPF 只认真实硬件输入，投递的 WM_LBUTTONDOWN 触发不了 Click。
# 而 Windows 的前台锁会让 SetForegroundWindow 静默失败，硬件点击就落到隔壁进程的窗口上
# （实测被一个浏览器窗口挡掉，误判成「程序点不动」），所以点之前先强行抢一次前台。
function Force-Foreground {
    $fgPid = 0
    $fg = [PG]::GetForegroundWindow()
    $fgTid = [PG]::GetWindowThreadProcessId($fg, [ref]$fgPid)
    $curTid = [PG]::GetCurrentThreadId()
    $attached = ($fgPid -ne 0 -and $fgTid -ne 0 -and $fgTid -ne $curTid)
    if ($attached) { [void][PG]::AttachThreadInput($curTid, $fgTid, $true) }
    [void][PG]::keybd_event(0x12, 0, 0, [IntPtr]::Zero)   # VK_MENU down
    [void][PG]::keybd_event(0x12, 0, 2, [IntPtr]::Zero)   # VK_MENU up
    [void][PG]::ShowWindow($hwnd, 5)
    [void][PG]::BringWindowToTop($hwnd)
    [void][PG]::SetForegroundWindow($hwnd)
    [void][PG]::SetActiveWindow($hwnd)
    if ($attached) { [void][PG]::AttachThreadInput($curTid, $fgTid, $false) }
    Start-Sleep -Milliseconds 250
}
function Click-At([int]$x, [int]$y) {
    Force-Foreground
    $pt = New-Object PG+PT; $pt.X = $x; $pt.Y = $y
    $under = [PG]::GetAncestor([PG]::WindowFromPoint($pt), 2)   # GA_ROOTOWNER
    if ($under -ne $hwnd) {
        Say ("OCCLUDED ({0},{1}) 命中 hwnd={2}，再抢一次前台" -f $x, $y, $under.ToInt64())
        Force-Foreground
    }
    [void][PG]::SetCursorPos($x, $y); Start-Sleep -Milliseconds 220
    [void][PG]::mouse_event(0x0002, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 90
    [void][PG]::mouse_event(0x0004, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 1400
}
function Element-Count {
    $w = Get-Window
    if (-not $w) { return -1 }
    return $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition).Count
}
# 导航只有左边那列 hc:SideMenu，它没有 UIA peer，「哪个菜单项选中」读不出来，
# 所以点完只退回 Element-Count 变化 + 截图两个判据。
function Nav-To([string]$label) {
    $before = Element-Count
    for ($try = 0; $try -lt 4; $try++) {
        $el = Find-El 'name' $label 2
        if (-not $el) { Say "MISS nav $label"; return }
        $r = $el.Current.BoundingRectangle
        Click-At ([int]($r.Left + $r.Width / 2)) ([int]($r.Top + $r.Height / 2))
        if ((Element-Count) -ne $before) { break }
    }
    Say ("NAV {0} 元素数 {1}" -f $label, (Element-Count))
}
# 开关点下去之后要看到 TogglePattern 的状态真的翻了，否则只是空转
function Toggle-State($el) {
    if (-not $el) { return 'Missing' }
    try {
        $tp = $el.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
        return [string]$tp.Current.ToggleState
    } catch { return 'NoPattern' }
}
function Toggle-ById([string]$id) {
    $el = Find-El 'id' $id
    if (-not $el) { Say "MISS toggle $id"; return }
    $before = Toggle-State $el
    $r = $el.Current.BoundingRectangle
    for ($try = 0; $try -lt 3; $try++) {
        Click-At ([int]($r.Left + $r.Width / 2)) ([int]($r.Top + $r.Height / 2))
        $el = Find-El 'id' $id 1
        if ((Toggle-State $el) -ne $before) { break }
    }
    Say ("TOGGLE {0} {1} -> {2}" -f $id, $before, (Toggle-State $el))
}
# 分项/总开关在关闭时应当是「禁用但仍在原位」（配合样式里 Opacity 0.4 的置灰）
function Pres([string]$id) {
    $el = Find-El 'id' $id 1
    if (-not $el) { Say "PRESENT $id = 不在 UIA 树里"; return }
    Say ("PRESENT {0} 可用={1} 勾选={2}" -f $id, $el.Current.IsEnabled, (Toggle-State $el))
}
# 按钮没有 TogglePattern，只能按矩形中心硬件点一下
function Click-ById([string]$id) {
    $el = Find-El 'id' $id
    if (-not $el) { Say "MISS button $id"; return }
    $r = $el.Current.BoundingRectangle
    Click-At ([int]($r.Left + $r.Width / 2)) ([int]($r.Top + $r.Height / 2))
}

if ($Run -eq '1') {
    Nav-To '工具设置'
    Save-Shot '01-settings-glass-light.png'
    # 当场切深浅色：整本字典换掉，主页背景与卡片应跟着变
    Toggle-ById 'DarkModeToggle'
    Save-Shot '02-settings-glass-dark.png'
    Nav-To '主页'
    Save-Shot '03-home-glass-dark.png'
    Pref-Dump '第1轮结束'
} elseif ($Run -eq '2') {
    # 不动任何开关，只证明上一轮的偏好（深色玻璃）被这次启动直接读回
    Nav-To '主页'
    Save-Shot '04-relaunch-glass-dark-home.png'
    Nav-To '工具设置'
    Save-Shot '05-relaunch-glass-dark-settings.png'
    Pres 'DarkModeToggle'
    Toggle-ById 'DarkModeToggle'
    Save-Shot '06-back-to-glass-light.png'
    Pref-Dump '第2轮结束'
} elseif ($Run -eq '3') {
    # 总开关关掉后：分项置灰但仍保留各自的值
    Nav-To '工具设置'
    Toggle-ById 'MotionShimmerToggle'
    Toggle-ById 'MotionMasterToggle'
    Save-Shot '08-motion-master-off.png'
    Toggle-ById 'MotionBreatheToggle'
    Save-Shot '09-subtoggle-while-master-off.png'
    Pref-Dump '第3轮结束'
} elseif ($Run -eq '4') {
    # 「恢复默认」应当把深浅色与动效全组拨回默认值，并且不需要重启（外观只剩液态玻璃一档）
    Nav-To '工具设置'
    Toggle-ById 'DarkModeToggle'
    Toggle-ById 'MotionMasterToggle'
    Save-Shot '10-before-reset-default.png'
    Click-ById 'ResetInterfaceSettingsButton'
    Save-Shot '11-after-reset-default.png'
    Pres 'DarkModeToggle'
    Pres 'MotionMasterToggle'
    Pres 'MotionShimmerToggle'
    Pref-Dump '第4轮结束'
}
Write-Output 'done'
if ($null -ne $cursorHome) { [void][PG]::SetCursorPos($cursorHome.X, $cursorHome.Y) }
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
