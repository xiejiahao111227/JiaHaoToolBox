param([string]$Exe, [string]$Manifest, [string]$OutDir)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @"
using System;using System.Runtime.InteropServices;
public struct RY{public int L;public int T;public int R;public int B;}
public class PY{
 [DllImport("user32.dll")]public static extern bool GetWindowRect(IntPtr h,out RY r);
 [DllImport("user32.dll")]public static extern bool PrintWindow(IntPtr h,IntPtr hdc,uint f);
 [DllImport("user32.dll")]public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")]public static extern void mouse_event(uint f,uint d,int x,int y,IntPtr e);
 [DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")]public static extern bool ShowWindow(IntPtr h,int c);
 [DllImport("user32.dll")]public static extern bool IsIconic(IntPtr h);
 [DllImport("user32.dll")]public static extern bool MoveWindow(IntPtr h,int x,int y,int w,int ht,bool repaint);
}
"@

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
# 清单文件：每行 "侧边栏项名称<TAB>输出文件名前缀[<TAB>页内二级点击目标]"，中文必须走 UTF-8 文件而不是 argv
$items = [System.IO.File]::ReadAllLines($Manifest, [System.Text.Encoding]::UTF8) |
    Where-Object { $_.Trim() -ne '' -and -not $_.StartsWith('#') } |
    ForEach-Object { $c = $_ -split "`t"; [pscustomobject]@{ Name = $c[0].Trim(); Tag = $c[1].Trim(); Sub = $(if ($c.Count -gt 2) { $c[2].Trim() } else { '' }) } }

function Invoke-Click($x, $y) {
    Restore-Win
    [void][PY]::SetCursorPos([int]$x, [int]$y)
    Start-Sleep -Milliseconds 250
    [PY]::mouse_event(2, 0, 0, 0, [IntPtr]::Zero)
    [PY]::mouse_event(4, 0, 0, 0, [IntPtr]::Zero)
}

$p = Start-Process -FilePath $Exe -PassThru
$deadline = (Get-Date).AddSeconds(60)
$hwnd = [IntPtr]::Zero
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 700; $p.Refresh()
    if ($p.HasExited) { Write-Output 'APP-EXITED-EARLY'; exit 1 }
    if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $hwnd = $p.MainWindowHandle; break }
}
if ($hwnd -eq [IntPtr]::Zero) { Write-Output 'NO-WINDOW'; Stop-Process -Id $p.Id -Force; exit 1 }
Start-Sleep -Seconds 18

$root = [System.Windows.Automation.AutomationElement]::RootElement
$cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
$win = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
if (-not $win) { Write-Output 'NO-AUTO-WINDOW'; Stop-Process -Id $p.Id -Force; exit 1 }

function Get-Tree($scopeWin) {
    return $scopeWin.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
}

function Restore-Win {
    for ($i = 0; $i -lt 6; $i++) {
        if (-not [PY]::IsIconic($hwnd)) { break }
        [void][PY]::ShowWindow($hwnd, 9)
        Start-Sleep -Milliseconds 300
    }
    [void][PY]::SetForegroundWindow($hwnd)
    Start-Sleep -Milliseconds 400
}

function Get-TreeFresh {
    # 点击后紧接着读树偶尔会返回空集合，重试几秒即可
    for ($t = 0; $t -lt 8; $t++) {
        $w = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
        # 应用失焦会缩到任务栏，此时整棵树坐标都是 -32000 哨兵值，点了也白点
        $rb = $w.Current.BoundingRectangle
        if ($rb.X -lt -30000) { Restore-Win; continue }
        $all = Get-Tree $w
        if ($all.Count -gt 0) { return $all }
        Start-Sleep -Milliseconds 800
    }
    return $null
}

function Save-Shot([string]$png) {
    if ([PY]::IsIconic($hwnd)) { [void][PY]::ShowWindow($hwnd, 9); Start-Sleep -Milliseconds 400 }
    [void][PY]::SetForegroundWindow($hwnd)
    Start-Sleep -Milliseconds 200
    $r = New-Object RY
    [void][PY]::GetWindowRect($hwnd, [ref]$r)
    $w = $r.R - $r.L; $h = $r.B - $r.T
    if ($w -lt 200 -or $h -lt 200) { Write-Output "   BAD-RECT $w x $h"; return }
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc()
    [void][PY]::PrintWindow($hwnd, $hdc, 2)
    $g.ReleaseHdc($hdc); $g.Dispose()
    $bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Output ("   shot {0} ({1}x{2})" -f $png, $w, $h)
}

function Dump-Tree([string]$tag) {
    $after = Get-TreeFresh
    if (-not $after) { $after = @() }
    $dump = New-Object System.Collections.Generic.List[string]
    foreach ($e in $after) {
        $n = $e.Current.Name
        if (-not $n) { continue }
        $bb = $e.Current.BoundingRectangle
        $dump.Add(("{0}`t{1}`t[{2},{3} {4}x{5}]" -f ($e.Current.ControlType.ProgrammaticName -replace 'ControlType\.', ''), $n, [int]$bb.X, [int]$bb.Y, [int]$bb.Width, [int]$bb.Height))
    }
    [System.IO.File]::WriteAllLines((Join-Path $OutDir ("tree-{0}.txt" -f $tag)), $dump, [System.Text.Encoding]::UTF8)
    return $dump
}

function Find-El([string]$name, [switch]$Right) {
    # 树偶尔只返回部分节点，找不到就多读几轮
    for ($k = 0; $k -lt 6; $k++) {
        foreach ($e in (Get-TreeFresh)) {
            if ($e.Current.Name -ne $name) { continue }
            $eb = $e.Current.BoundingRectangle
            if ($eb.Width -le 0 -or $eb.Height -le 0) { continue }
            # 侧边栏在左列，页面内容在右侧，同名元素靠 x 区分
            if ($Right) { if ($eb.X -lt 440) { continue } }
            elseif ($eb.X -gt 440 -or $eb.Y -lt 40 -or $eb.Y -gt 800) { continue }
            return $e
        }
        Start-Sleep -Seconds 1
    }
    return $null
}

foreach ($it in $items) {
    Start-Sleep -Milliseconds 1500
    # 应用会在失焦时缩到任务栏，读树之前先还原窗口
    [void][PY]::ShowWindow($hwnd, 9)
    [void][PY]::SetForegroundWindow($hwnd)
    Start-Sleep -Milliseconds 400
    # 每次重新获取窗口元素，否则 UIA 客户端缓存会给出点击前的旧树
    $hit = Find-El $it.Name
    if (-not $hit) { Write-Output "MISS: $($it.Name)"; continue }
    $b = $hit.Current.BoundingRectangle

    $x = [int]($b.X + $b.Width / 2); $y = [int]($b.Y + $b.Height / 2)
    Invoke-Click $x $y
    # 部分页面首次进入会同步拉取数据，UI 线程要等一会儿才重绘
    Start-Sleep -Seconds 8

    if ($it.Sub -ne '') {
        # 磁贴要求双击（e.ClickCount != 2 直接 return），清单里用 @ 前缀标记
        $name = $it.Sub; $dbl = $false
        if ($name.StartsWith('@')) { $dbl = $true; $name = $name.Substring(1) }
        $sub = Find-El $name -Right
        if (-not $sub) { Write-Output "MISS-SUB: $name"; continue }
        $sb = $sub.Current.BoundingRectangle
        if ($dbl) {
            Invoke-Click ($sb.X + $sb.Width / 2) ($sb.Y + $sb.Height / 2)
            Start-Sleep -Milliseconds 90
            [PY]::mouse_event(2, 0, 0, 0, [IntPtr]::Zero)
            [PY]::mouse_event(4, 0, 0, 0, [IntPtr]::Zero)
        } else {
            Invoke-Click ($sb.X + $sb.Width / 2) ($sb.Y + $sb.Height / 2)
        }
        Start-Sleep -Seconds 5
    }

    Save-Shot (Join-Path $OutDir ("shot-{0}.png" -f $it.Tag))
    $dump = Dump-Tree $it.Tag
    Write-Output ("OK {0} @ {1},{2} -> {3} elements" -f $it.Name, $x, $y, $dump.Count)
}

Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
