# Crops the captured browser screenshots (shots.tsv: id <TAB> source jpg <TAB> x1,y1,x2,y2) into
# LoWsTourAssets/screens/<id>.jpg (JPEG q85: the static resource must stay under 5 MB), scaled down to at most 1280 px wide.
param([string]$Map = "$PSScriptRoot\shots.tsv", [string]$Out = "$PSScriptRoot\LoWsTourAssets\screens")
Add-Type -AssemblyName System.Drawing
foreach ($line in Get-Content $Map) {
  $id, $src, $box = $line -split "`t"
  $x1, $y1, $x2, $y2 = $box -split ',' | ForEach-Object { [int]$_ }
  $img = [System.Drawing.Image]::FromFile($src)
  $w = $x2 - $x1; $h = $y2 - $y1
  $scale = [Math]::Min(1.0, 1280.0 / $w)
  $tw = [int]($w * $scale); $th = [int]($h * $scale)
  $bmp = New-Object System.Drawing.Bitmap $tw, $th
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = 'HighQualityBicubic'
  $g.DrawImage($img, (New-Object System.Drawing.Rectangle 0, 0, $tw, $th), (New-Object System.Drawing.Rectangle $x1, $y1, $w, $h), 'Pixel')
  $enc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq "image/jpeg" }; $ep = New-Object System.Drawing.Imaging.EncoderParameters 1; $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality, [long]85); $bmp.Save("$Out\$id.jpg", $enc, $ep)
  $g.Dispose(); $bmp.Dispose(); $img.Dispose()
  "$id ${tw}x$th"
}
