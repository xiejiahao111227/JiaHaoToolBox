param([string]$Exe, [string]$OutDir)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;using System.Runtime.InteropServices;
public struct RG{public int L;public int T;public int R;public int B;}
public class PG{
 [DllImport("user32.dll")]public static extern bool GetWindowRect(IntPtr h,out RG r);
 [DllImport("user32.dll")]public static extern bool PrintWindow(IntPtr h,IntPtr hdc,uint f);
 [DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr h);
}
"@
function Say([string]$m) { [Console]::Out.WriteLine($m) }
$p = Start-Process -FilePath $Exe -PassThru
$deadline = (Get-Date).AddSeconds(60); $hwnd = [IntPtr]::Zero
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 700; $p.Refresh()
    if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $hwnd = $p.MainWindowHandle; break }
}
Start-Sleep -Seconds 9
[void][PG]::SetForegroundWindow($hwnd)
function Grab {
    $r = New-Object RG; [void][PG]::GetWindowRect($hwnd, [ref]$r)
    $w = $r.R - $r.L; $h = $r.B - $r.T
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc(); [void][PG]::PrintWindow($hwnd, $hdc, 2); $g.ReleaseHdc($hdc); $g.Dispose()
    return $bmp
}
# 取主页右下角一块只有玻璃卡片和背景的区域，间隔采样比较，证明光斑真的在漂
$a = Grab
Start-Sleep -Seconds 8
$b = Grab
$diff = 0; $moved = 0
for ($y = 560; $y -lt 740; $y += 2) {
    for ($x = 640; $x -lt 960; $x += 2) {
        $c1 = $a.GetPixel($x, $y); $c2 = $b.GetPixel($x, $y)
        $d = [Math]::Abs($c1.R - $c2.R) + [Math]::Abs($c1.G - $c2.G) + [Math]::Abs($c1.B - $c2.B)
        if ($d -gt 6) { $moved++ }
        if ($d -gt 0) { $diff++ }
    }
}
$total = ((740 - 560) / 2) * ((960 - 640) / 2)
Say ("采样 $total 点：有变化 $diff 点，明显变化(>6) $moved 点")
$a.Dispose(); $b.Dispose()
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
