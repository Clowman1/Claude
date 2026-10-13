param([string]$Out, [string[]]$Ids)
# O4h: placeholder JPEGs (same look as phaseO4e build-assets.ps1) for shots not captured yet. Real captures overwrite them.
Add-Type -AssemblyName System.Drawing
$jpeg = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$q = New-Object System.Drawing.Imaging.EncoderParameters 1
$q.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), 85L
foreach ($id in $Ids) {
  $bw = 640; $bh = 360
  $b = New-Object System.Drawing.Bitmap $bw,$bh
  $g = [System.Drawing.Graphics]::FromImage($b)
  $g.Clear([System.Drawing.Color]::FromArgb(241,245,249))
  $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(148,163,184)), 3
  $pen.DashStyle = 'Dash'
  $g.DrawRectangle($pen, 6, 6, $bw-13, $bh-13)
  $font = New-Object System.Drawing.Font 'Segoe UI', 22, ([System.Drawing.FontStyle]::Bold)
  $small = New-Object System.Drawing.Font 'Segoe UI', 12
  $fmt = New-Object System.Drawing.StringFormat; $fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
  $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(51,65,85))
  $g.TextRenderingHint = 'AntiAlias'
  $g.DrawString($id, $font, $brush, (New-Object System.Drawing.RectangleF 0,0,$bw,($bh-30)), $fmt)
  $g.DrawString('Screenshot placeholder', $small, $brush, (New-Object System.Drawing.RectangleF 0,40,$bw,($bh-30)), $fmt)
  $b.Save("$Out\$id.jpg", $jpeg, $q)
  $g.Dispose(); $b.Dispose()
}
"done"
