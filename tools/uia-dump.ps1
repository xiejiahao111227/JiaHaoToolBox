param(
    [string]$Exe,
    [string]$Out,
    [string]$Filter = '',
    [switch]$ClickAndCapture,
    [string]$CaptureOut = '',
    [string]$NameFile = ''
)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
# 中文经 argv 传到 PowerShell 会被破坏，目标名称改用 UTF-8 文件读取
if ($NameFile) { $Filter = ([System.IO.File]::ReadAllText($NameFile, [System.Text.Encoding]::UTF8)).Trim() }
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @"
using System;using System.Runtime.InteropServices;
public struct RZ{public int L;public int T;public int R;public int B;}
public class PZ{
 [DllImport("user32.dll")]public static extern bool GetWindowRect(IntPtr h,out RZ r);
 [DllImport("user32.dll")]public static extern bool PrintWindow(IntPtr h,IntPtr hdc,uint f);
 [DllImport("user32.dll")]public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")]public static extern void mouse_event(uint f,uint d,int x,int y,IntPtr e);
 [DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr h);
}
"@

$p = Start-Process -FilePath $Exe -PassThru
$deadline = (Get-Date).AddSeconds(60)
$hwnd = [IntPtr]::Zero
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 700; $p.Refresh()
    if ($p.HasExited) { Write-Output 'APP-EXITED-EARLY'; exit 1 }
    if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $hwnd = $p.MainWindowHandle; break }
}
if ($hwnd -eq [IntPtr]::Zero) { Write-Output 'NO-WINDOW'; Stop-Process -Id $p.Id -Force; exit 1 }
Start-Sleep -Seconds 8

$root = [System.Windows.Automation.AutomationElement]::RootElement
$cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
$win = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
if (-not $win) { Write-Output 'NO-AUTO-WINDOW'; Stop-Process -Id $p.Id -Force; exit 1 }

$wr = New-Object RZ
[void][PZ]::GetWindowRect($hwnd, [ref]$wr)
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("WINDOW rect: $($wr.L),$($wr.T) - $($wr.R),$($wr.B)")

$all = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
$lines.Add("ELEMENTS: $($all.Count)")
foreach ($e in $all) {
    $n = $e.Current.Name
    if (-not $n) { continue }
    $b = $e.Current.BoundingRectangle
    $ct = $e.Current.ControlType.ProgrammaticName -replace 'ControlType\.', ''
    $vis = $e.Current.IsOffscreen
    $lines.Add(("{0}`t{1}`t[{2},{3} {4}x{5}]`toffscreen={6}" -f $ct, $n, [int]$b.X, [int]$b.Y, [int]$b.Width, [int]$b.Height, $vis))
}
[System.IO.File]::WriteAllLines($Out, $lines, [System.Text.Encoding]::UTF8)
Write-Output "dumped $($lines.Count) lines -> $Out"

if ($Filter) {
    Write-Output "=== 命中过滤 '$Filter' ==="
    $hits = $lines | Where-Object { $_ -like "*$Filter*" }
    if (-not $hits) { Write-Output '(无)' } else { $hits | ForEach-Object { Write-Output $_ } }
}

if ($ClickAndCapture -and $CaptureOut) {
    $targetName = $Filter
    $hit = $null
    foreach ($e in $all) { if ($e.Current.Name -eq $targetName) { $hit = $e; break } }
    if (-not $hit) { Write-Output "CLICK-TARGET-NOT-FOUND: $targetName"; Stop-Process -Id $p.Id -Force; exit 1 }

    # 命中的常常是菜单项内部的 Text 元素，需要向上找到可交互的容器（SideMenuItem 等）
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $node = $hit
    for ($i = 0; $i -lt 4; $i++) {
        $parent = $walker.GetParent($node)
        if (-not $parent) { break }
        $pt = $parent.Current.ControlType.ProgrammaticName
        if ($pt -match 'ListItem|Custom|Button|Group|TabItem') { $node = $parent; break }
        $node = $parent
    }
    Write-Output ("click target resolved to {0} '{1}'" -f ($node.Current.ControlType.ProgrammaticName -replace 'ControlType\.',''), $node.Current.Name)

    [void][PZ]::SetForegroundWindow($hwnd)
    Start-Sleep -Milliseconds 500
    $done = $false
    $sp = $null
    if ($node.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$sp)) {
        $sp.Select(); $done = $true; Write-Output 'invoked via SelectionItemPattern'
    }
    if (-not $done) {
        $ip = $null
        if ($node.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$ip)) {
            $ip.Invoke(); $done = $true; Write-Output 'invoked via InvokePattern'
        }
    }
    if (-not $done) {
        $b = $node.Current.BoundingRectangle
        $cx = [int]($b.X + $b.Width / 2); $cy = [int]($b.Y + $b.Height / 2)
        Write-Output "click at $cx,$cy"
        [void][PZ]::SetCursorPos($cx, $cy)
        Start-Sleep -Milliseconds 400
        [PZ]::mouse_event(2, 0, 0, 0, [IntPtr]::Zero)
        [PZ]::mouse_event(4, 0, 0, 0, [IntPtr]::Zero)
    }
    Start-Sleep -Seconds 4
    $r = New-Object RZ
    [void][PZ]::GetWindowRect($hwnd, [ref]$r)
    $w = $r.R - $r.L; $h = $r.B - $r.T
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc()
    [void][PZ]::PrintWindow($hwnd, $hdc, 2)
    $g.ReleaseHdc($hdc); $g.Dispose()
    $bmp.Save($CaptureOut, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Output "captured $w x $h -> $CaptureOut"
}

Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
