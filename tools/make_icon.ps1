<#
  Draws the Feather app icon (a quill on a dark rounded square) with System.Drawing and
  writes windows/runner/resources/app_icon.ico (PNG-compressed entries 16…256) plus
  assets/feather.png for use inside the app.
#>
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent

function Draw([int]$size) {
  $bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'
  $g.InterpolationMode = 'HighQualityBicubic'
  $g.PixelOffsetMode = 'HighQuality'
  $s = $size / 256.0
  $g.ScaleTransform($s, $s)

  # Rounded dark square.
  $r = 58
  $bg = New-Object System.Drawing.Drawing2D.GraphicsPath
  $bg.AddArc(8, 8, $r, $r, 180, 90); $bg.AddArc(248 - $r, 8, $r, $r, 270, 90)
  $bg.AddArc(248 - $r, 248 - $r, $r, $r, 0, 90); $bg.AddArc(8, 248 - $r, $r, $r, 90, 90); $bg.CloseFigure()
  $bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.PointF 0, 0), (New-Object System.Drawing.PointF 256, 256), ([System.Drawing.Color]::FromArgb(255, 44, 44, 46)), ([System.Drawing.Color]::FromArgb(255, 24, 24, 26))
  $g.FillPath($bgBrush, $bg)
  $g.DrawPath((New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(70, 255, 255, 255)), 2), $bg)

  # Feather vane: long and asymmetric, leaning to the top right.
  $vane = New-Object System.Drawing.Drawing2D.GraphicsPath
  $vane.AddBezier(84, 196, 56, 150, 112, 70, 208, 40)
  $vane.AddBezier(208, 40, 196, 96, 156, 168, 100, 204)
  $vane.CloseFigure()
  $vaneBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.PointF 70, 210), (New-Object System.Drawing.PointF 208, 40), ([System.Drawing.Color]::FromArgb(255, 190, 88, 56)), ([System.Drawing.Color]::FromArgb(255, 242, 160, 120))
  $g.FillPath($vaneBrush, $vane)

  # V notches cut into both edges, slanting toward the tip like real barbs.
  $bgc = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 34, 34, 36))
  $g.FillPolygon($bgc, [System.Drawing.PointF[]]@((New-Object System.Drawing.PointF 66, 146), (New-Object System.Drawing.PointF 104, 132), (New-Object System.Drawing.PointF 76, 124)))
  $g.FillPolygon($bgc, [System.Drawing.PointF[]]@((New-Object System.Drawing.PointF 104, 96), (New-Object System.Drawing.PointF 134, 96), (New-Object System.Drawing.PointF 114, 82)))
  $g.FillPolygon($bgc, [System.Drawing.PointF[]]@((New-Object System.Drawing.PointF 184, 116), (New-Object System.Drawing.PointF 156, 124), (New-Object System.Drawing.PointF 176, 134)))

  # Quill (shaft), running past the vane at the bottom.
  $shaft = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255, 250, 244, 236)), 7
  $shaft.StartCap = 'Round'; $shaft.EndCap = 'Round'
  $q = New-Object System.Drawing.Drawing2D.GraphicsPath
  $q.AddBezier(50, 222, 96, 172, 150, 108, 200, 50)
  $g.DrawPath($shaft, $q)
  $g.Dispose()
  return $bmp
}

$sizes = 16, 20, 24, 32, 40, 48, 64, 128, 256
$pngs = @()
foreach ($sz in $sizes) {
  $b = Draw $sz
  $ms = New-Object System.IO.MemoryStream
  $b.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
  $pngs += , $ms.ToArray()
  if ($sz -eq 256) { $b.Save((Join-Path $root 'assets\feather.png'), [System.Drawing.Imaging.ImageFormat]::Png) }
  $b.Dispose()
}

# ICO container with PNG entries.
$ico = Join-Path $root 'windows\runner\resources\app_icon.ico'
$fs = [System.IO.File]::Create($ico)
$w = New-Object System.IO.BinaryWriter $fs
$w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
  $sz = $sizes[$i]; $data = $pngs[$i]
  $w.Write([byte]($(if ($sz -ge 256) { 0 } else { $sz }))); $w.Write([byte]($(if ($sz -ge 256) { 0 } else { $sz })))
  $w.Write([byte]0); $w.Write([byte]0); $w.Write([uint16]1); $w.Write([uint16]32)
  $w.Write([uint32]$data.Length); $w.Write([uint32]$offset)
  $offset += $data.Length
}
foreach ($data in $pngs) { $w.Write($data) }
$w.Close()
Write-Host "icon -> $ico"
