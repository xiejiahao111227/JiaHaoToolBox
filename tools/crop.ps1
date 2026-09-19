param([string]$In,[string]$Out,[int]$X,[int]$Y,[int]$W,[int]$H,[int]$Scale)
Add-Type -AssemblyName System.Drawing
$src = [System.Drawing.Image]::FromFile($In)
$dst = New-Object System.Drawing.Bitmap ($W*$Scale), ($H*$Scale)
$g = [System.Drawing.Graphics]::FromImage($dst)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$destRect = New-Object System.Drawing.Rectangle 0,0,($W*$Scale),($H*$Scale)
$srcRect  = New-Object System.Drawing.Rectangle $X,$Y,$W,$H
$g.DrawImage($src, $destRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose(); $src.Dispose()
$dst.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$dst.Dispose()
Write-Output "ok"
