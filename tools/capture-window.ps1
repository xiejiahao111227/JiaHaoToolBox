param([string]$Exe, [string]$Out)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;using System.Runtime.InteropServices;
public struct RECT2{public int L;public int T;public int R;public int B;}
public class PW{
 [DllImport("user32.dll")]public static extern bool GetWindowRect(IntPtr h,out RECT2 r);
 [DllImport("user32.dll")]public static extern bool PrintWindow(IntPtr h,IntPtr hdc,uint flags);
 [DllImport("user32.dll")]public static extern bool IsWindow(IntPtr h);
 [DllImport("user32.dll")]public static extern IntPtr GetDC(IntPtr h);
 [DllImport("user32.dll")]public static extern int ReleaseDC(IntPtr h,IntPtr dc);
}
"@
$p = Start-Process -FilePath $Exe -PassThru
$deadline = (Get-Date).AddSeconds(45)
$hwnd = [IntPtr]::Zero
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 700
    $p.Refresh()
    if ($p.HasExited) { Write-Output 'APP-EXITED-EARLY'; exit 1 }
    if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $hwnd = $p.MainWindowHandle; break }
}
if ($hwnd -eq [IntPtr]::Zero) { Write-Output 'NO-MAIN-WINDOW'; Stop-Process -Id $p.Id -Force; exit 1 }
Start-Sleep -Seconds 6
$r = New-Object RECT2
[void][PW]::GetWindowRect($hwnd, [ref]$r)
$w = $r.R - $r.L; $h = $r.B - $r.T
if ($w -le 0 -or $h -le 0) { Write-Output "BAD-RECT $w x $h"; Stop-Process -Id $p.Id -Force; exit 1 }
$bmp = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::Transparent)
$hdc = $g.GetHdc()
[void][PW]::PrintWindow($hwnd, $hdc, 2)   # PW_RENDERFULLCONTENT
$g.ReleaseHdc($hdc)
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Output ("captured {0}x{1} title='{2}' -> {3}" -f $w, $h, $p.MainWindowTitle, $Out)
Stop-Process -Id $p.Id -Force
