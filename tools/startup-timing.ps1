param([string]$Exe, [string]$MarkerFile, [int]$Runs = 3)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

# 遮罩层文案（含中文，从 UTF-8 文件读，不走 argv）
$marker = [System.IO.File]::ReadAllText($MarkerFile, [System.Text.Encoding]::UTF8).Trim()
$root = [System.Windows.Automation.AutomationElement]::RootElement

for ($i = 1; $i -le $Runs; $i++) {
    $t0 = Get-Date
    $p = Start-Process -FilePath $Exe -PassThru
    $tShow = $null; $tReady = $null; $tFirstTree = $null
    $deadline = $t0.AddSeconds(40)
    while ((Get-Date) -lt $deadline) {
        $p.Refresh()
        if ($p.HasExited) { break }
        if ($null -eq $tShow -and $p.MainWindowHandle -ne [IntPtr]::Zero) {
            $tShow = Get-Date
            # 窗口句柄出现后再探一次 UIA，能拿到树说明排版已开始
            $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
            $w = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
            if ($w) { $tFirstTree = Get-Date }
        }
        if ($null -ne $tShow) {
            $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)
            $w = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
            $hit = $false
            if ($w) {
                $tc = [System.Windows.Automation.Condition]::TrueCondition
                foreach ($e in $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, $tc)) {
                    if ($e.Current.Name -eq $marker) { $hit = $true; break }
                }
            }
            if (-not $hit) { $tReady = Get-Date; break }
        }
        Start-Sleep -Milliseconds 30
    }
    $msShow = if ($tShow) { [int]($tShow - $t0).TotalMilliseconds } else { -1 }
    $msTree = if ($tFirstTree) { [int]($tFirstTree - $t0).TotalMilliseconds } else { -1 }
    $msReady = if ($tReady) { [int]($tReady - $t0).TotalMilliseconds } else { -1 }
    Write-Output ("run {0}: 窗口句柄 {1}ms / UIA 可用 {2}ms / 遮罩消失 {3}ms" -f $i, $msShow, $msTree, $msReady)
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}
