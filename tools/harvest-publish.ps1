param(
    [string]$Root = 'publish',
    [string]$Dst = 'setup\files.wxs'
)

$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
if (-not (Test-Path $Root)) { throw "找不到 $Root 目录，请先执行 dotnet publish" }

$rootFull = (Resolve-Path $Root).Path.TrimEnd('\')

function Get-Id([string]$key, [string]$prefix) {
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $hash = ($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($key.ToLowerInvariant())) |
        ForEach-Object { $_.ToString('x2') }) -join ''
    return "${prefix}_" + $hash.Substring(0, 16)
}

function Esc([string]$s) {
    return $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
}

$allFiles = Get-ChildItem -LiteralPath $rootFull -Recurse -File |
    ForEach-Object { [pscustomobject]@{
        Rel = $_.FullName.Substring($rootFull.Length + 1)
        Full = $_.FullName
        Size = $_.Length
    } } | Sort-Object Rel

if ($allFiles.Count -eq 0) { throw "$Root 下没有文件" }

# 目录树：键为相对路径（反斜杠），值为 {Id,Name,Children}
$dirs = @{}
$dirs[''] = @{ Id = 'INSTALLFOLDER'; Name = 'JiaHaoToolBox'; Children = @{} }
foreach ($f in $allFiles) {
    if ($f.Rel -notlike '*\*') { continue }
    $segs = $f.Rel.Split('\')
    $parentKey = ''
    for ($i = 0; $i -lt $segs.Count - 1; $i++) {
        $key = $segs[0..$i] -join '\'
        if (-not $dirs.ContainsKey($key)) {
            $dirs[$key] = @{ Id = (Get-Id "dir|$key" 'dir'); Name = $segs[$i]; Children = @{} }
            $dirs[$parentKey].Children[$key] = $true
        }
        $parentKey = $key
    }
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">')
[void]$sb.AppendLine('  <!-- 由 tools\harvest-publish.ps1 依据 publish\ 目录自动生成，请勿手工编辑 -->')

# 1) 目录结构：INSTALLFOLDER 下的子目录树
[void]$sb.AppendLine('  <Fragment>')
[void]$sb.AppendLine('    <DirectoryRef Id="INSTALLFOLDER">')
function Write-Dirs($parentKey, $indent) {
    foreach ($childKey in ($dirs[$parentKey].Children.Keys | Sort-Object)) {
        $d = $dirs[$childKey]
        if ($d.Children.Count -eq 0) {
            [void]$script:sb.AppendLine("$indent<Directory Id=`"$($d.Id)`" Name=`"$(Esc $d.Name)`" />")
        } else {
            [void]$script:sb.AppendLine("$indent<Directory Id=`"$($d.Id)`" Name=`"$(Esc $d.Name)`">")
            Write-Dirs $childKey ($indent + '  ')
            [void]$script:sb.AppendLine("$indent</Directory>")
        }
    }
}
Write-Dirs '' '      '
[void]$sb.AppendLine('    </DirectoryRef>')
[void]$sb.AppendLine('  </Fragment>')

# 2) 文件组件
[void]$sb.AppendLine('  <Fragment>')
[void]$sb.AppendLine('    <ComponentGroup Id="PublishFiles" Directory="INSTALLFOLDER">')
foreach ($f in $allFiles) {
    $parentRel = if ($f.Rel.Contains('\')) { ($f.Rel.Split('\')[0..($f.Rel.Split('\').Count - 2)]) -join '\' } else { '' }
    $dirId = $dirs[$parentRel].Id
    # WiX 5 的相对 Source 路径解析基准不稳定，直接写绝对路径
    $src = $rootFull + '\' + $f.Rel
    [void]$sb.AppendLine("      <Component Id=`"$(Get-Id "cmp|$($f.Rel)" 'cmp')`" Directory=`"$dirId`">")
    [void]$sb.AppendLine("        <File Id=`"$(Get-Id "fil|$($f.Rel)" 'fil')`" Source=`"$(Esc $src)`" KeyPath=`"yes`" />")
    [void]$sb.AppendLine('      </Component>')
}
[void]$sb.AppendLine('    </ComponentGroup>')
[void]$sb.AppendLine('  </Fragment>')
[void]$sb.AppendLine('</Wix>')

$dir = Split-Path -Parent $Dst
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
[System.IO.File]::WriteAllText((Join-Path (Get-Location) $Dst), $sb.ToString(), [System.Text.Encoding]::ASCII)

$totalSize = (($allFiles | Measure-Object -Property Size -Sum).Sum / 1MB)
Write-Host "已收集 $($allFiles.Count) 个文件 / $($dirs.Count - 1) 个子目录 / $([math]::Round($totalSize,1)) MB -> $Dst"
