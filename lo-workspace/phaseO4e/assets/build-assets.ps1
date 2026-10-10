param([string]$Poses, [string]$Out)
Add-Type -AssemblyName System.Drawing
Remove-Item -Recurse -Force $Out -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force "$Out\poses","$Out\screens" | Out-Null
Get-ChildItem "$Poses\*.png" | ForEach-Object { if ($_.Name -ne 'bran-hands-on-hips.png') { Copy-Item $_.FullName "$Out\poses\$($_.Name)" } }

# hands-on-hips: cut at the first fully transparent column run (>= 8 px) after the body, right of centre.
$src = New-Object System.Drawing.Bitmap "$Poses\bran-hands-on-hips.png"
$cut = $src.Width; $run = 0
for ($x = [int]($src.Width/2); $x -lt $src.Width; $x++) {
  $empty = $true
  for ($y = 0; $y -lt $src.Height; $y += 1) { if ($src.GetPixel($x,$y).A -gt 10) { $empty = $false; break } }
  if ($empty) { $run++; if ($run -ge 8) { $cut = $x - $run + 4; break } } else { $run = 0 }
}
$dst = $src.Clone((New-Object System.Drawing.Rectangle 0,0,$cut,$src.Height), $src.PixelFormat)
$dst.Save("$Out\poses\bran-hands-on-hips.png", [System.Drawing.Imaging.ImageFormat]::Png)
"hands-on-hips cut at x=$cut of $($src.Width)"
$dst.Dispose(); $src.Dispose()

# head-and-shoulders crop of waving
$w = New-Object System.Drawing.Bitmap "$Poses\bran-waving.png"
$h = $w.Clone((New-Object System.Drawing.Rectangle 122,25,198,198), $w.PixelFormat)
$h.Save("$Out\poses\bran-head.png", [System.Drawing.Imaging.ImageFormat]::Png)
$h.Dispose(); $w.Dispose()

$ids = 'SS-UPNEXT','SS-ALERT','SS-RECENT','SS-BOARD','SS-LEAD','SS-ZOOM','SS-TEXTS','SS-TEXTS-LOAN','SS-DOCREQ','SS-LETTER','SS-APPSUM','SS-TRID','SS-PREAPP','SS-SUBMIT','SS-LOANS','SS-LOAN','SS-REALTORS','SS-REALTOR','SS-PASTCLIENT','SS-CAL','SS-EVENTS','SS-INVESTORS','SS-PHONE-1','SS-PHONE-2','SS-PHONE-3','SS-PHONE-4'
foreach ($id in $ids) {
  if ($id -like 'SS-PHONE*') { $bw = 300; $bh = 600 } else { $bw = 640; $bh = 360 }
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
  $b.Save("$Out\screens\$id.png", [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $b.Dispose()
}
"done"
