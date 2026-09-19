param([string]$Exe)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$p = Start-Process -FilePath $Exe -PassThru
$deadline = (Get-Date).AddSeconds(60)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 700; $p.Refresh()
    if ($p.MainWindowHandle -ne [IntPtr]::Zero) { break }
}
Start-Sleep -Seconds 8
$AU = [System.Windows.Automation.AutomationElement]
$root = $AU::RootElement
$cond = New-Object System.Windows.Automation.PropertyCondition($AU::ProcessIdProperty, $p.Id)
$kids = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cond)
$win = $null
for ($i = 0; $i -lt $kids.Count; $i++) {
    $k = $kids.Item($i)
    Write-Output ("TOP[$i] name='{0}' class='{1}' rect={2}" -f $k.Current.Name, $k.Current.ClassName, $k.Current.BoundingRectangle)
    if (-not $win -and $k.Current.Name -eq '嘉豪工具箱') { $win = $k }
}
if (-not $win) { Write-Output 'NO-WINDOW-ELEMENT'; Stop-Process -Id $p.Id -Force; exit 1 }
$all = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
Write-Output "DESCENDANTS $($all.Count)"
$ids = @()
foreach ($e in $all) { if ($e.Current.AutomationId) { $ids += $e.Current.AutomationId } }
Write-Output ("IDS({0}): {1}" -f $ids.Count, (($ids | Select-Object -First 120) -join ','))
$menu = New-Object System.Windows.Automation.PropertyCondition($AU::ClassNameProperty, 'SideMenuItem')
$items = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $menu)
Write-Output "SIDEMENUITEMS $($items.Count)"
for ($i = 0; $i -lt $all.Count; $i++) {
    $e = $all.Item($i)
    Write-Output ("  E[{0}] class='{1}' ctrl={2} name='{3}' rect={4}" -f $i, $e.Current.ClassName, $e.Current.ControlType.ProgrammaticName, $e.Current.Name, $e.Current.BoundingRectangle)
}
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
