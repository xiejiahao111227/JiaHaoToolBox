param([string]$Exe, [string]$NameFile, [string]$OutFile)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$name = ([System.IO.File]::ReadAllLines($NameFile, [System.Text.Encoding]::UTF8) | Where-Object { $_.Trim() -ne '' } | Select-Object -First 1).Trim()

$p = Start-Process -FilePath $Exe -PassThru
$deadline = (Get-Date).AddSeconds(60)
$hwnd = [IntPtr]::Zero
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 700; $p.Refresh()
    if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $hwnd = $p.MainWindowHandle; break }
}
Start-Sleep -Seconds 9
$root = [System.Windows.Automation.AutomationElement]::RootElement
$cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
$win = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
$out = New-Object System.Collections.Generic.List[string]
$all = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
$out.Add("total=$($all.Count) target=$name")
$hit = $null
foreach ($e in $all) { if ($e.Current.Name -eq $name) { $hit = $e; break } }
if (-not $hit) { $out.Add('NOT-FOUND'); [System.IO.File]::WriteAllLines($OutFile, $out, [System.Text.Encoding]::UTF8); Stop-Process -Id $p.Id -Force; exit }
$walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
$node = $hit
for ($i = 0; $i -lt 6; $i++) {
    if (-not $node) { break }
    $pats = ($node.GetSupportedPatterns() | ForEach-Object { $_.ProgrammaticName }) -join ','
    $b = $node.Current.BoundingRectangle
    $out.Add(("{0}`tclass={1}`t[{2},{3} {4}x{5}]`tpatterns={6}" -f ($node.Current.ControlType.ProgrammaticName -replace 'ControlType\.', ''), $node.Current.ClassName, [int]$b.X, [int]$b.Y, [int]$b.Width, [int]$b.Height, $pats))
    $node = $walker.GetParent($node)
}
[System.IO.File]::WriteAllLines($OutFile, $out, [System.Text.Encoding]::UTF8)
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
