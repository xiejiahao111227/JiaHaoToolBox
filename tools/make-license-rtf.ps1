param(
    [string]$Src = 'LICENSE',
    [string]$Dst = 'setup\license.rtf'
)

$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

function ConvertTo-RtfText([string]$s) {
    $out = New-Object System.Text.StringBuilder
    foreach ($ch in $s.ToCharArray()) {
        if ($ch -eq '\') { [void]$out.Append('\\'); continue }
        if ($ch -eq '{') { [void]$out.Append('\{'); continue }
        if ($ch -eq '}') { [void]$out.Append('\}'); continue }
        $code = [int]$ch
        if ($code -lt 128) { [void]$out.Append($ch); continue }
        if ($code -gt 32767) { $code -= 65536 }
        [void]$out.Append('\u' + $code + '?')
    }
    return $out.ToString()
}

$text = [System.IO.File]::ReadAllText((Resolve-Path $Src)) -replace "`r`n", "`n"
$lines = $text -split "`n"

$Attribution = '本安装包为嘉豪工具箱（JiaHaoToolBox）安装程序。嘉豪工具箱是基于 GPL-3.0-or-later 许可证、由紫罗兰工具箱（VioletToolBox）项目衍生修改而来的作品，上游版权归 Smart-Paocai 及其贡献者所有。安装并使用本程序即表示你接受下列 GNU GPLv3 条款。'

$rtf = New-Object System.Text.StringBuilder
[void]$rtf.Append('{\rtf1\ansi\ansicpg1252\deff0\deflang1033{\fonttbl{\f0\fnil\fcharset134 Consolas;}}\viewkind4\uc1')
[void]$rtf.Append("`r`n" + '\pard\qc\b\f0\fs28 ' + (ConvertTo-RtfText '嘉豪工具箱 JiaHaoToolBox 安装程序') + '\b0\fs20\par')
[void]$rtf.Append("`r`n" + '\qc ' + (ConvertTo-RtfText ('版本 1.2.0（测试版 V1.2 / OS1.0.2.0.UMNMIXM）')) + '\par\par')
[void]$rtf.Append("`r`n" + '\ql\fs18 ' + (ConvertTo-RtfText $Attribution) + '\par\par')
[void]$rtf.Append("`r`n" + '\pard\qc\b\fs24 ' + (ConvertTo-RtfText 'GNU GENERAL PUBLIC LICENSE') + '\b0\fs20\par\par')
foreach ($line in $lines) {
    [void]$rtf.Append("`r`n" + '\fs18 ' + (ConvertTo-RtfText $line) + '\par')
}
[void]$rtf.Append("`r`n" + '}')

$dir = Split-Path -Parent $Dst
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
# 非 ASCII 字符已全部转为 \u 转义，文件本身是纯 ASCII，用 ASCII 编码落盘最稳妥。
[System.IO.File]::WriteAllText($Dst, $rtf.ToString(), [System.Text.Encoding]::ASCII)
Write-Host "$Dst <- $Src : $($lines.Count) 行, $((Get-Item $Dst).Length) 字节"
