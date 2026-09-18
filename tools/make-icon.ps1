Add-Type -AssemblyName System.Drawing

function New-Surface([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $r = [Math]::Max(4, [int]($size * 0.22))
    $d = [double]$r * 2
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0, 0, $d, $d, 180, 90)
    $path.AddArc($size - $r * 2, 0, $d, $d, 270, 90)
    $path.AddArc($size - $r * 2, $size - $r * 2, $d, $d, 0, 90)
    $path.AddArc(0, $size - $r * 2, $d, $d, 90, 90)
    $path.CloseFigure()
    $rect = New-Object System.Drawing.Rectangle(0, 0, $size, $size)
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $rect,
        [System.Drawing.Color]::FromArgb(255, 76, 42, 158),
        [System.Drawing.Color]::FromArgb(255, 37, 24, 84),
        [System.Drawing.Drawing2D.LinearGradientMode]::ForwardDiagonal)
    $g.FillPath($brush, $path)
    $g.DrawPath((New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(70, 255, 255, 255), [Math]::Max(1, $size / 64))), $path)

    # lightning bolt, normalised into a 100x100 box then scaled
    $pts = @(
        @(56, 12), @(30, 54), @(46, 54), @(38, 88), @(70, 44), @(52, 44)
    ) | ForEach-Object {
        New-Object System.Drawing.PointF([float]($_[0] / 100 * $size), [float]($_[1] / 100 * $size))
    }
    $g.FillPolygon([System.Drawing.Brushes]::White, $pts)
    $g.Dispose()
    return $bmp
}

$sizes = @(256, 128, 64, 48, 32, 16)
$pngs = foreach ($s in $sizes) {
    $bmp = New-Surface $s
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    @{ Size = $s; Bytes = $ms.ToArray() }
    $ms.Dispose()
}

# ICO container with PNG payloads (Vista+): ICONDIR + ICONDIRENTRY[] + data
$out = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($out)
$bw.Write([UInt16]0)
$bw.Write([UInt16]1)                       # type: icon
$bw.Write([UInt16]$pngs.Count)
$offset = 6 + 16 * $pngs.Count
foreach ($p in $pngs) {
    $dim = if ($p.Size -ge 256) { 0 } else { $p.Size }
    $bw.Write([Byte]$dim)                  # width  (0 == 256)
    $bw.Write([Byte]$dim)                  # height
    $bw.Write([Byte]0)                     # palette
    $bw.Write([Byte]0)                     # reserved
    $bw.Write([UInt16]1)                   # planes
    $bw.Write([UInt16]32)                  # bpp
    $bw.Write([UInt32]$p.Bytes.Length)
    $bw.Write([UInt32]$offset)
    $offset += $p.Bytes.Length
}
foreach ($p in $pngs) { $bw.Write($p.Bytes) }
$bw.Flush()

$target = Join-Path $PSScriptRoot 'JiaHaoToolBox.ico'
[System.IO.File]::WriteAllBytes($target, $out.ToArray())
$bw.Dispose(); $out.Dispose()
Write-Host "wrote $target ($((Get-Item $target).Length) bytes)"
