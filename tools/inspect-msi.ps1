param([string]$Msi)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
# 用 Windows Installer COM 读安装包元数据，确认名称/版本/作用域/语言都写对了
$wi = New-Object -ComObject WindowsInstaller.Installer
$view = $wi.GetType().InvokeMember('OpenDatabase', 'InvokeMethod', $null, $wi, @($Msi, 0))
$sum = $view.GetType().InvokeMember('SummaryInformation', 'GetProperty', $null, $view, 0)
Write-Output ('ProductName    : ' + $sum.GetType().InvokeMember('Property', 'GetProperty', $null, $sum, 2))
Write-Output ('ProductVersion : ' + $sum.GetType().InvokeMember('Property', 'GetProperty', $null, $sum, 3))
Write-Output ('Template       : ' + $sum.GetType().InvokeMember('Property', 'GetProperty', $null, $sum, 1))
Write-Output ('Subject        : ' + $sum.GetType().InvokeMember('Property', 'GetProperty', $null, $sum, 4))
Write-Output ('Author         : ' + $sum.GetType().InvokeMember('Property', 'GetProperty', $null, $sum, 6))
Write-Output ('PackageCode    : ' + $sum.GetType().InvokeMember('Property', 'GetProperty', $null, $sum, 13))
Write-Output ('Template       : ' + $sum.GetType().InvokeMember('Property', 'GetProperty', $null, $sum, 7))
Write-Output ('LastSavedBy    : ' + $sum.GetType().InvokeMember('Property', 'GetProperty', $null, $sum, 8))
$pv = $view.GetType().InvokeMember('OpenView', 'InvokeMethod', $null, $view, 'SELECT `Property`, `Value` FROM Property')
[void]$pv.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $pv, $null)
$want = @('ProductName', 'ProductVersion', 'ProductCode', 'UpgradeCode', 'ALLUSERS', 'ARPPRODUCTNAME', 'ARPINSTALLLOCATION', 'MSIINSTALLPERFORMANCE', 'WixUI_InstallDir', 'ARPCOMMENTS')
while ($true) {
    $row = $pv.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $pv, $null)
    if ($null -eq $row) { break }
    $k = $row.GetType().InvokeMember('StringData', 'GetProperty', $null, $row, 1)
    if ($want -contains $k) {
        Write-Output ($k + ' = ' + $row.GetType().InvokeMember('StringData', 'GetProperty', $null, $row, 2))
    }
}
$st = $view.GetType().InvokeMember('OpenView', 'InvokeMethod', $null, $view, 'SELECT `Value` FROM Property WHERE `Property`=''ProductLanguage''')
[void]$st.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $st, $null)
$r = $st.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $st, $null)
while ($r -ne $null) { Write-Output ('ProductLanguage  : ' + $r.GetType().InvokeMember('StringData', 'GetProperty', $null, $r, 1)); $r = $st.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $st, $null) }
$fc = $view.GetType().InvokeMember('OpenView', 'InvokeMethod', $null, $view, 'SELECT `File`, `FileName` FROM File')
[void]$fc.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $fc, $null)
$n = 0
while ($fc.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $fc, $null) -ne $null) { $n++ }
Write-Output ('FileTableRows  : ' + $n)
