[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Get-EventLog -LogName Application -Newest 40 |
  Where-Object { $_.EntryType -ne 'Information' } |
  Select-Object -First 6 |
  ForEach-Object {
    Write-Output ('=== ' + $_.TimeGenerated + ' | ' + $_.Source)
    Write-Output ($_.Message.Substring(0, [Math]::Min(1200, $_.Message.Length)))
  }
