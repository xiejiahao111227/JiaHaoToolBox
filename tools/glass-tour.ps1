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
 [DllImport("user32.dll")]public static extern bool GetCursorPos(out PT p);
 [DllImport("user32.dll")]public static extern void mouse_event(uint f,uint d,uint e,IntPtr x);
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
function Say([string]$m) { [Console]::Out.WriteLine($m) }
$AU = [System.Windows.Automation.AutomationElement]
$root = $AU::RootElement

# 主题与动效用偏好文件预设（顺带验证启动早期读取）；UIA Invoke 主题按钮会连发两次 Click，不可靠
$prefDir = Join-Path $env:LOCALAPPDATA 'JiaHaoTool'
$pref = Join-Path $prefDir 'settings.txt'
$legacy = Join-Path $prefDir 'theme.txt'
if (-not (Test-Path $prefDir)) { New-Item -ItemType Directory -Path $prefDir -Force | Out-Null }
if ((Test-Path $pref) -or (Test-Path $legacy)) { Remove-Item $pref, $legacy -Force -ErrorAction SilentlyContinue }
# Motion 未指定时按动效开处理，和程序内默认值保持一致
$mo = if ($Motion) { $Motion } else { '1' }
if ($StartDark -or $mo -eq '0' -or $Pref) {
    $lines = @(
        ('theme=' + $(if ($StartDark) { 'Dark' } else { 'Light' })),
        "motion=$mo"
    )
    foreach ($kv in @($Pref -split ',')) { if ($kv) { $lines += $kv } }
    Set-Content -Path $pref -Value ($lines -join "`r`n") -Encoding UTF8 -NoNewline
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
            # 必须挑「不在屏幕外」的那一个：同名元素可能有俩——左栏 SideMenuItem 的标题文字，
            # 和此刻 Collapsed 掉的页面上那个同名 TextBlock（矩形在 -32000 附近）。
            # FindFirst 会先撞上后者，点下去什么也不会发生。
            $all = $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, $c)
            for ($i = 0; $i -lt $all.Count; $i++) {
                if (-not $all.Item($i).Current.IsOffscreen) { return $all.Item($i) }
            }
        }
        Start-Sleep -Milliseconds 600
    }
    return $null
}

function Say([string]$m) { [Console]::Out.WriteLine($m) }
function Theme-State {
    # 偏好文件里记下外观模式与动效开关，截图文件名对得上才说明是「按预设启动」而不是默认值
    $f = Join-Path $env:LOCALAPPDATA 'JiaHaoTool\settings.txt'
    if (-not (Test-Path $f)) { return '默认玻璃浅色' }
    $kv = @{}
    foreach ($line in (Get-Content $f)) { $i = $line.IndexOf('='); if ($i -gt 0) { $kv[$line.Substring(0,$i).Trim()] = $line.Substring($i+1).Trim() } }
    # 顺带打一个分项值，好核对「落盘的动效开关」和「截图上看到的动效」是不是同一套
    $mode = if ($kv['theme'] -eq 'Dark') { '玻璃深' } else { '玻璃浅' }
    return ('{0} 动效={1}/{2}' -f $mode, $kv['motion'], $kv['motion.shimmer'])
}
function Element-Count {
    $w = Get-Window
    if (-not $w) { return -1 }
    return $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition).Count
}

# SideMenuItem 没有自动化面板，只能点它的标题文字。实测 WPF 只认真实硬件输入：
# SendMessage/PostMessage 投递的 WM_LBUTTONDOWN 能改 hover 却触发不了 Click，所以这里用 SetCursorPos + mouse_event。
# Windows 的前台锁还会让 SetForegroundWindow 静默失败：桌面上挂着别的窗口（比如浏览器）时，硬件点击会落到
# 那个窗口上，脚本却以为"页面点了没反应"（曾经巡检后半段四个导航项全卡住就是这么来的）。
# 这里先 AttachThreadInput 到前台线程、敲一次 ALT 解锁，再 BringWindowToTop + SetForegroundWindow 硬抢。
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
    [void][PG]::SetCursorPos($x, $y)
    Start-Sleep -Milliseconds 220
    [void][PG]::mouse_event(0x0002, 0, 0, [IntPtr]::Zero)   # LEFTDOWN
    Start-Sleep -Milliseconds 90
    [void][PG]::mouse_event(0x0004, 0, 0, [IntPtr]::Zero)   # LEFTUP
    Start-Sleep -Milliseconds 1200
}
# 导航只有左边那列 hc:SideMenu，它不进 UIA 树、读不出选中态，
# 所以导航成功与否只能退回元素数变化 + 截图两个判据。
function Nav-To([string]$label, [string]$view) {
    $before = Element-Count
    for ($try = 0; $try -lt 4; $try++) {
        # 每一轮都重读矩形再点正中：拿旧坐标点在隔壁项上，截图就会张冠李戴
        $el = Find-ByName $label 6
        if (-not $el) { Say "MISS $label"; return }
        $r = $el.Current.BoundingRectangle
        [void][PG]::SetForegroundWindow($hwnd)
        Start-Sleep -Milliseconds 250
        Click-At ([int]($r.Left + $r.Width / 2)) ([int]($r.Top + $r.Height / 2))
        if ((Element-Count) -ne $before) { break }
    }
    Say ("NAV {0} -> {1} 元素数 {2} 主题 {3}" -f $label, $view, (Element-Count), (Theme-State))
}

# 导航标题 -> 截图文件名。玻璃档点的是左侧 hc:SideMenuItem 标题文字（SideMenuItem 不进 UIA 树，
# 只能按文字定位），所以这里全程按标题文字找矩形再硬件点击。
$tour = [ordered]@{
    '主页'     = 'Home'
    '投屏'     = 'ScreenMirror'
    '基本刷入' = 'BasicFlash'
    '可视刷写' = 'FastbootVis'
    '欧加线刷' = 'OujiaFlash'
    'EDL刷写'  = 'EdlFlash'
    '降级助手' = 'ColorOS'
    '模块专区' = 'HiddenEnv'
    '断点续传' = 'VioletDownload'
    '文件传输' = 'SystemZone'
    '脱机修补' = 'Autoroot'
    '应用管理' = 'AppManager'
    '安卓通用' = 'AndroidGeneral'
    'Payload'  = 'Payload'
    '备份助手' = 'BackupAssistant'
    '下载专区' = 'Download'
    'Rom专区'  = 'RomDownload'
    '工具设置' = 'ToolSettings'
    '关于'     = 'About'
}
# $Only='Home,ToolSettings' 只跑其中几页：整轮 19 页要三分多钟，PowerShell 5.1 的 AMSI 段错误
# 会让 ps-enc 从头再来一遍，页面越少越不容易撞上重试。
if ($Only) {
    $keep = @($Only -split ',')
    $picked = [ordered]@{}
    foreach ($k in @($tour.Keys)) { if ($keep -contains $tour[$k]) { $picked[$k] = $tour[$k] } }
    $tour = $picked
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
