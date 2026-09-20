# WPF 工具箱的 UIA/Win32 巡检公共库：被各 check 脚本 dot-source 使用（本机 PowerShell 5.1 会把
# 单个大脚本整块送进 AMSI 扫描，脚本一大就随机段错误，所以把公共 helper 拆出去、驱动脚本保持小）。
# 约定：调用方给 $Exe/$OutDir/$pref，本库把当前主窗口句柄放在 $global:hwnd、进程条件放在 $global:cond。
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
 [DllImport("user32.dll",EntryPoint="GetWindowLongPtrW")]public static extern IntPtr GetWindowLongPtr(IntPtr h,int idx);
 public struct PT{public int X;public int Y;}
}
"@
function Say([string]$line) { [Console]::Out.WriteLine($line) }
$AU = [System.Windows.Automation.AutomationElement]
$root = $AU::RootElement

# 进程内换不掉的东西只能用窗口样式当证据：这几个位是结论所在
$WS_THICKFRAME = 0x00040000
$WS_CAPTION = 0x00C00000
$WS_MINIMIZEBOX = 0x00020000
$WS_EX_LAYERED = 0x00080000

function Style-Line([IntPtr]$h) {
    if ($h -eq [IntPtr]::Zero) { return 'no-window' }
    $style = [PG]::GetWindowLongPtr($h, -16).ToInt64()
    $ex = [PG]::GetWindowLongPtr($h, -20).ToInt64()
    $bits = @()
    if ($style -band $WS_THICKFRAME) { $bits += 'THICKFRAME' } else { $bits += '!THICKFRAME' }
    if ($style -band $WS_CAPTION) { $bits += 'CAPTION' } else { $bits += '!CAPTION' }
    if ($style -band $WS_MINIMIZEBOX) { $bits += 'MINBOX' }
    if ($ex -band $WS_EX_LAYERED) { $bits += 'LAYERED' } else { $bits += '!LAYERED' }
    return ("style=0x{0:X8} exstyle=0x{1:X8} [{2}]" -f $style, $ex, ($bits -join ' '))
}
function CommandLine([int]$id) {
    try { return [string](Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction Stop).CommandLine }
    catch { return '?' }
}

$global:hwnd = [IntPtr]::Zero
$global:cond = $null
function Get-Window {
    $kids = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $global:cond)
    for ($i = 0; $i -lt $kids.Count; $i++) { if ($kids.Item($i).Current.ClassName -eq 'Window') { return $kids.Item($i) } }
    return $null
}
# 每次重启后句柄、进程、UIA 条件全都要重绑，沿用旧 hwnd 读到的是上一个进程的样式
function Bind-Process([System.Diagnostics.Process]$p) {
    $global:cond = New-Object System.Windows.Automation.PropertyCondition($AU::ProcessIdProperty, $p.Id)
    $deadline = (Get-Date).AddSeconds(60); $global:hwnd = [IntPtr]::Zero
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500; $p.Refresh()
        if ($p.HasExited) { continue }
        $w = Get-Window
        if ($w) {
            $rw = New-Object RG
            # 窗口刚建好时矩形还在 0x0，这时候读样式位没意义
            if ([PG]::GetWindowRect($p.MainWindowHandle, [ref]$rw) -and ($rw.R - $rw.L) -ge 400) {
                $global:hwnd = $p.MainWindowHandle; return $true
            }
        }
        if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $global:hwnd = $p.MainWindowHandle }
    }
    return ($global:hwnd -ne [IntPtr]::Zero)
}
# 换外观会换进程：新 PID 必须和老的不同，否则说明根本没重启。
# 注意别在 ForEach-Object 里 return：那只结束那个脚本块，函数照样走到末尾的 return $null。
function Wait-Next([int]$oldPid) {
    $deadline = (Get-Date).AddSeconds(45)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 600
        $others = @(Get-Process -Name 'JiaHaoToolBox' -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $oldPid })
        if ($others.Count -gt 0) { return $others[0] }
    }
    return $null
}
function Wait-Exit([int]$id) {
    $deadline = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $deadline) {
        $gone = Get-Process -Id $id -ErrorAction SilentlyContinue
        if (-not $gone) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}
function Find-El([string]$by, [string]$value, [int]$tries = 6) {
    for ($k = 0; $k -lt $tries; $k++) {
        $w = Get-Window
        if ($w) {
            $prop = if ($by -eq 'id') { $AU::AutomationIdProperty } else { $AU::NameProperty }
            # 同名元素会有俩（左栏标题文字 / 被收起的顶部标签按钮，后者矩形在 -32000 附近），只挑不在屏幕外的
            $all = $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition($prop, $value)))
            for ($i = 0; $i -lt $all.Count; $i++) { if (-not $all.Item($i).Current.IsOffscreen) { return $all.Item($i) } }
        }
        Start-Sleep -Milliseconds 600
    }
    return $null
}
# WPF 只认真实硬件输入，而 Windows 的前台锁会让 SetForegroundWindow 静默失败，
# 硬件点击就会落到隔壁窗口上，所以点之前先强行抢一次前台。
function Force-Foreground {
    $fgPid = 0
    $fg = [PG]::GetForegroundWindow()
    $fgTid = [PG]::GetWindowThreadProcessId($fg, [ref]$fgPid)
    $curTid = [PG]::GetCurrentThreadId()
    $attached = ($fgPid -ne 0 -and $fgTid -ne 0 -and $fgTid -ne $curTid)
    if ($attached) { [void][PG]::AttachThreadInput($curTid, $fgTid, $true) }
    [void][PG]::keybd_event(0x12, 0, 0, [IntPtr]::Zero)
    [void][PG]::keybd_event(0x12, 0, 2, [IntPtr]::Zero)
    [void][PG]::ShowWindow($global:hwnd, 5)
    [void][PG]::BringWindowToTop($global:hwnd)
    [void][PG]::SetForegroundWindow($global:hwnd)
    [void][PG]::SetActiveWindow($global:hwnd)
    if ($attached) { [void][PG]::AttachThreadInput($curTid, $fgTid, $false) }
    Start-Sleep -Milliseconds 250
}
function Click-At([int]$x, [int]$y, [int]$waitMs = 1200) {
    Force-Foreground
    $pt = New-Object PG+PT; $pt.X = $x; $pt.Y = $y
    $under = [PG]::GetAncestor([PG]::WindowFromPoint($pt), 2)
    if ($under -ne $global:hwnd) { Say ("OCCLUDED ({0},{1}) 命中 hwnd={2}，再抢一次前台" -f $x, $y, $under.ToInt64()); Force-Foreground }
    [void][PG]::SetCursorPos($x, $y); Start-Sleep -Milliseconds 220
    [void][PG]::mouse_event(0x0002, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 90
    [void][PG]::mouse_event(0x0004, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds $waitMs
}
function Click-ByName([string]$label) {
    $el = Find-El 'name' $label
    if (-not $el) { Say "MISS $label"; return $false }
    $r = $el.Current.BoundingRectangle
    Click-At ([int]($r.Left + $r.Width / 2)) ([int]($r.Top + $r.Height / 2))
    return $true
}
function Click-ById([string]$id) {
    $el = Find-El 'id' $id
    if (-not $el) { Say "MISS $id"; return $false }
    $r = $el.Current.BoundingRectangle
    Click-At ([int]($r.Left + $r.Width / 2)) ([int]($r.Top + $r.Height / 2))
    return $true
}
function Click-Radio([string]$id) {
    $el = Find-El 'id' $id
    if (-not $el) { Say "MISS radio $id"; return $false }
    $r = $el.Current.BoundingRectangle
    Click-At ([int]($r.Left + $r.Width / 2)) ([int]($r.Top + $r.Height / 2)) 200
    return $true
}
# 单选的真实勾选态读 SelectionItemPattern（RadioButton 没有 TogglePattern）
function Radio-On([string]$id) {
    $el = Find-El 'id' $id 2
    if (-not $el) { return 'Missing' }
    try { return $el.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Current.Selected }
    catch { return 'NoPattern' }
}
# 原生对话框（MessageBox 之类）是同一个进程下的 #32770 顶层窗口，不在 WPF 那棵 UIA 树里，
# 只能从桌面根节点按 PID 找。按钮是标准 Win32 按钮，InvokePattern 直接点得动，不需要抢前台。
function Get-Dialog {
    $kids = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $global:cond)
    for ($i = 0; $i -lt $kids.Count; $i++) { if ($kids.Item($i).Current.ClassName -eq '#32770') { return $kids.Item($i) } }
    return $null
}
function Wait-Dialog([int]$tries = 14) {
    for ($k = 0; $k -lt $tries; $k++) { $d = Get-Dialog; if ($d) { return $d }; Start-Sleep -Milliseconds 250 }
    return $null
}
function Dialog-Texts($dlg) {
    $all = $dlg.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
    $t = @()
    for ($i = 0; $i -lt $all.Count; $i++) {
        $e = $all.Item($i)
        if ($e.Current.Name) { $t += ('{0}="{1}"' -f $e.Current.ControlType.ProgrammaticName.Replace('ControlType.', ''), $e.Current.Name) }
    }
    return ($t -join ' ')
}
function Dialog-Click($dlg, [string]$btnName) {
    if (-not $dlg) { return $false }
    $all = $dlg.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition($AU::NameProperty, $btnName)))
    for ($i = 0; $i -lt $all.Count; $i++) {
        try { $all.Item($i).GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep -Milliseconds 500; return $true } catch { }
    }
    return $false
}
function Print-Hwnd([IntPtr]$h, [string]$png) {
    $r = New-Object RG
    for ($i = 0; $i -lt 8; $i++) {
        [void][PG]::GetWindowRect($h, [ref]$r)
        if (($r.R - $r.L) -ge 60 -and ($r.B - $r.T) -ge 40) { break }
        Start-Sleep -Milliseconds 250
    }
    $w = $r.R - $r.L; $hh = $r.B - $r.T
    if ($w -lt 60 -or $hh -lt 40) { Say "BAD-RECT $png"; return $false }
    $bmp = New-Object System.Drawing.Bitmap($w, $hh)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc(); [void][PG]::PrintWindow($h, $hdc, 2); $g.ReleaseHdc($hdc); $g.Dispose()
    $bmp.Save((Join-Path $OutDir $png), [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    Say ("shot {0} ({1}x{2})" -f $png, $w, $hh)
    return $true
}
function Save-HwndShot([IntPtr]$h, [string]$png) { [void](Print-Hwnd $h $png) }
function Save-Shot([string]$png) {
    if ($global:hwnd -eq [IntPtr]::Zero) { Say "NO-WINDOW $png"; return }
    for ($i = 0; $i -lt 12; $i++) {
        [void][PG]::ShowWindow($global:hwnd, 9); [void][PG]::SetForegroundWindow($global:hwnd)
        Start-Sleep -Milliseconds 500
        $r = New-Object RG; [void][PG]::GetWindowRect($global:hwnd, [ref]$r)
        if (($r.R - $r.L) -ge 400 -and ($r.B - $r.T) -ge 400) {
            $w = $r.R - $r.L; $h = $r.B - $r.T
            $bmp = New-Object System.Drawing.Bitmap($w, $h)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $hdc = $g.GetHdc(); [void][PG]::PrintWindow($global:hwnd, $hdc, 2); $g.ReleaseHdc($hdc); $g.Dispose()
            $bmp.Save((Join-Path $OutDir $png), [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
            Say ("shot {0} ({1}x{2})" -f $png, $w, $h); return
        }
    }
    Say "BAD-RECT $png"
}
function Element-Count {
    $w = Get-Window
    if (-not $w) { return -1 }
    return $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition).Count
}
function Pref-Dump([string]$tag) {
    if (-not (Test-Path $pref)) { Say "PREF[$tag] <无文件>"; return }
    Say ("PREF[{0}] {1}" -f $tag, (((Get-Content $pref) | Where-Object { $_ } | ForEach-Object { $_.Trim() }) -join ' '))
}
