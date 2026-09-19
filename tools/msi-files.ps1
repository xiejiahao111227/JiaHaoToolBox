# msi-files: 从 File 表确认安装包内容。第 1 行会被 ps-enc 丢掉。
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$wi = New-Object -ComObject WindowsInstaller.Installer
$view = $wi.GetType().InvokeMember('OpenDatabase', 'InvokeMethod', $null, $wi, @($Msi, 0))
$q = "SELECT ``FileName``, ``FileSize`` FROM File"
$rv = $view.GetType().InvokeMember('OpenView', 'InvokeMethod', $null, $view, $q)
[void]$rv.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $rv, $null)
$total = 0; $bytes = 0; $hits = @{}
$keys = 'JiaHaoToolBox.dll', 'JiaHaoToolBox.exe', 'adb.exe', 'fastboot.exe', 'NOTICE.txt', 'HandyControl.dll', 'JiaHaoToolBox.exe.config'
while ($true) {
    $row = $rv.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $rv, $null)
    if ($null -eq $row) { break }
    $name = $row.GetType().InvokeMember('StringData', 'GetProperty', $null, $row, 1)
    $size = [int]$row.GetType().InvokeMember('StringData', 'GetProperty', $null, $row, 2)
    $total++; $bytes += $size
    $short = ($name -split '\|')[-1]
    foreach ($k in $keys) { if ($short -eq $k) { $hits[$k] = '{0}  ({1:N0} 字节)' -f $short, $size } }
}
Write-Output ("MSI 内文件总数: {0}，合计 {1:N1} MB" -f $total, ($bytes / 1MB))
foreach ($k in $keys) { if ($hits.ContainsKey($k)) { Write-Output ('  命中 ' + $hits[$k]) } else { Write-Output ('  缺失 ' + $k) } }
