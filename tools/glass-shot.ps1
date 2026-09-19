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
 [DllImport("user32.dll")]public static extern bool IsIconic(IntPtr h);
}
"@
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

$p = Start-Process -FilePath $Exe -PassThru
$deadline = (Get-Date).AddSeconds(60); $hwnd = [IntPtr]::Zero
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 700; $p.Refresh()
    if ($p.HasExited) { Write-Output 'APP-EXITED-EARLY'; exit 1 }
    if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $hwnd = $p.MainWindowHandle; break }
}
if ($hwnd -eq [IntPtr]::Zero) { Write-Output 'NO-WINDOW'; Stop-Process -Id $p.Id -Force; exit 1 }
Start-Sleep -Seconds 6

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
    Write-Output ("shot {0} ({1}x{2})" -f $png, $w, $h)
}

$root = [System.Windows.Automation.AutomationElement]::RootElement
$cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
function Find-ById([string]$id) {
    for ($k = 0; $k -lt 8; $k++) {
        $w = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
        if ($w) {
            $c = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, $id)
            $e = $w.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $c)
            if ($e) { return $e }
        }
        Start-Sleep -Milliseconds 800
    }
    return $null
}

# 起始状态固定为浅色（跑之前先删掉 %LOCALAPPDATA%\JiaHaoTool\theme.txt），文件名才和实际配色对得上
Save-Shot (Join-Path $OutDir 'home-light.png')
$btn = Find-ById 'GlassThemeToggleButton'
if (-not $btn) { Write-Output 'TOGGLE-NOT-FOUND'; Stop-Process -Id $p.Id -Force; exit 1 }
$pat = $btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
$pat.Invoke()
Start-Sleep -Seconds 2
Save-Shot (Join-Path $OutDir 'home-dark.png')
# 版本徽章点击后应跳转到「关于」页：用来确认换肤没把导航打断
$badge = Find-ById 'VersionBadgeButton'
if ($badge) {
    $bp = $badge.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    $bp.Invoke()
    Start-Sleep -Seconds 4
    Save-Shot (Join-Path $OutDir 'about-dark.png')
} else { Write-Output 'BADGE-NOT-FOUND' }
Write-Output 'done'
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
