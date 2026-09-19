param([switch]$DryRun)
$ErrorActionPreference = 'Stop'
$root = Join-Path $PSScriptRoot '..\JiaHaoToolBox'

# 文件名 -> Icons.xaml 资源键，与 IconGen 的映射规则保持一致
$map = @{}
foreach ($line in Get-Content (Join-Path $PSScriptRoot 'icon-manifest.tsv')) {
  $p = $line -split "`t"
  if ($p.Count -ge 3 -and $p[0] -ne 'FAIL') { $map[$p[1]] = $p[2] }
}
Write-Output ("manifest keys: {0}" -f $map.Count)

foreach ($f in @('MainWindow.xaml', 'Window1.xaml')) {
  $p = Join-Path $root $f
  $c = [IO.File]::ReadAllText($p)
  $orig = $c
  $missing = @()

  # 0) 驱动列表模板把 Source 绑定到 SVG 路径字符串，只能继续用 SharpVectors，先保护起来
  $c = [regex]::Replace($c, '<svg:SvgViewbox(?=\s*\r?\n?\s*Source="\{Binding IconSource\}")', '@@KEEP@@')

  # 1) SVG 路径先换成占位符，再按映射表落成资源键
  $c = [regex]::Replace($c, 'Source="(?:pack://application:,,,/)?images/([^"]*?)\.svg"', 'Source="@@SVG::$1@@"')

  foreach ($name in @($map.Keys)) {
    $c = $c.Replace('Source="@@SVG::' + $name + '@@"', 'Source="{StaticResource ' + $map[$name] + '}"')
  }
  foreach ($m in [regex]::Matches($c, 'Source="@@SVG::([^@]*)@@"')) { $missing += $m.Groups[1].Value }
  $c = [regex]::Replace($c, 'Source="@@SVG::([^@]*)@@"', 'Source="images/$1.svg"')

  # 2) 元素与属性元素改名
  $c = $c -replace '<svg:SvgViewbox\.Style>', '<Image.Style>'
  $c = $c -replace '</svg:SvgViewbox\.Style>', '</Image.Style>'
  $c = $c -replace '<svg:SvgViewbox', '<Image'
  $c = $c -replace '</svg:SvgViewbox>', '</Image>'
  # 3) 样式 TargetType 改名
  $c = $c -replace 'TargetType="\{x:Type svg:SvgViewbox\}"', 'TargetType="{x:Type Image}"'
  $c = $c -replace 'TargetType="svg:SvgViewbox"', 'TargetType="Image"'
  # 4) 还原被保护的元素
  $c = $c -replace '@@KEEP@@', '<svg:SvgViewbox'

  $keys = ([regex]::Matches($c, 'Source="\{StaticResource ic_')).Count
  $left = ([regex]::Matches($c, 'svg:SvgViewbox')).Count
  Write-Output ("{0,-18} icons={1,3} kept-svg-sites={2,2} unmapped={3}" -f $f, $keys, $left, (($missing | Sort-Object -Unique) -join ','))
  if (-not $DryRun) {
    [IO.File]::WriteAllText($p, $c, (New-Object System.Text.UTF8Encoding($true)))
  }
}
