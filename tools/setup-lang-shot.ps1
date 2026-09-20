param([string]$Setup, [string]$OutDir, [string]$Name = 'setup')
# 只把安装向导开在第一页截图，然后直接结束进程：还没走到写注册表/落文件那步，强杀不留残留。
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
}
"@
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
function Say([string]$line) { [Console]::Out.WriteLine($line) }
$AU = [System.Windows.Automation.AutomationElement]
$root = $AU::RootElement

$p = Start-Process -FilePath $Setup -PassThru
$deadline = (Get-Date).AddSeconds(60); $hwnd = [IntPtr]::Zero
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 600; $p.Refresh()
    if ($p.HasExited) { Say 'SETUP-EXITED-EARLY'; exit 1 }
    if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $hwnd = $p.MainWindowHandle; break }
}
if ($hwnd -eq [IntPtr]::Zero) { Say 'NO-WINDOW'; Stop-Process -Id $p.Id -Force; exit 1 }
Start-Sleep -Seconds 3
$cond = New-Object System.Windows.Automation.PropertyCondition($AU::ProcessIdProperty, $p.Id)
$w = $null
$kids = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
Say ("TOP 进程 {0} 顶层窗口数 {1}" -f $p.Id, $kids.Count)
for ($i = 0; $i -lt $kids.Count; $i++) {
    $k = $kids.Item($i)
    Say ("  [{0}] class={1} 标题=「{2}」" -f $i, $k.Current.ClassName, $k.Current.Name)
    if (-not $w -and $k.Current.ClassName -eq '#32770') { $w = $k }
}
$r = New-Object RG
for ($i = 0; $i -lt 10; $i++) {
    [void][PG]::ShowWindow($hwnd, 5); [void][PG]::SetForegroundWindow($hwnd)
    Start-Sleep -Milliseconds 400
    [void][PG]::GetWindowRect($hwnd, [ref]$r)
    if (($r.R - $r.L) -ge 300) { break }
}
$bw = $r.R - $r.L; $bh = $r.B - $r.T
if ($bw -lt 300 -or $bh -lt 200) { Say "BAD-RECT $bw x $bh"; Stop-Process -Id $p.Id -Force; exit 1 }
$bmp = New-Object System.Drawing.Bitmap($bw, $bh)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc(); [void][PG]::PrintWindow($hwnd, $hdc, 2); $g.ReleaseHdc($hdc); $g.Dispose()
$png = Join-Path $OutDir ("{0}.png" -f $Name)
$bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
Say ("shot {0} ({1}x{2})" -f $png, $bw, $bh)
# 页面上的文字全部来自 MessagesFile，逐条打出来才能确认不是「只有标题是中文」
if ($w) {
    $texts = $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition($AU::ControlTypeProperty, [System.Windows.Automation.ControlType]::Text)))
    for ($i = 0; $i -lt $texts.Count; $i++) {
        $t = $texts.Item($i).Current.Name
        if ($t) { Say ("TEXT {0}" -f ($t -replace "`r`n", ' / ')) }
    }
    $btns = $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition($AU::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)))
    for ($i = 0; $i -lt $btns.Count; $i++) {
        $t = $btns.Item($i).Current.Name
        if ($t) { Say ("BUTTON {0}" -f $t) }
    }
}
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
Write-Output 'done'
