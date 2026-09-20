param([string]$A, [string]$B)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing
function Say([string]$text) { [Console]::Out.WriteLine($text) }
$ia = [System.Drawing.Image]::FromFile($A)
$ib = [System.Drawing.Image]::FromFile($B)
Say ("{0} vs {1}  {2}x{3} / {4}x{5}" -f (Split-Path $A -Leaf), (Split-Path $B -Leaf), $ia.Width, $ia.Height, $ib.Width, $ib.Height)
if ($ia.Width -ne $ib.Width -or $ia.Height -ne $ib.Height) { Say 'SIZE-DIFFERENT'; exit 0 }
$ca = New-Object System.Drawing.Bitmap $ia
$cb = New-Object System.Drawing.Bitmap $ib
$same = 0; $near = 0; $far = 0
for ($y = 0; $y -lt $ca.Height; $y += 2) {
    for ($x = 0; $x -lt $ca.Width; $x += 2) {
        $p = $ca.GetPixel($x, $y); $q = $cb.GetPixel($x, $y)
        $d = [Math]::Abs($p.R - $q.R) + [Math]::Abs($p.G - $q.G) + [Math]::Abs($p.B - $q.B)
        if ($d -eq 0) { $same++ } elseif ($d -le 12) { $near++ } else { $far++ }
    }
}
$total = $same + $near + $far
Say ("采样 $total 点：完全相同 $same（{0:N1}%） 轻微 $near 明显 $far（{1:N1}%）" -f (100.0 * $same / $total), (100.0 * $far / $total))
$ca.Dispose(); $cb.Dispose(); $ia.Dispose(); $ib.Dispose()
