# Adapted from yoursAnthony/XiaomiPCManager-Locale-Patch (MIT) - see THIRD_PARTY_NOTICES.md
# Changes: images whose layout does not match expectations are skipped with a warning
# instead of aborting the whole set.
param(
    [Parameter(Mandatory = $true)][string]$InputDirectory,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [Parameter(Mandatory = $true)][string]$FontPath,
    [Parameter(Mandatory = $true)][string]$Text
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $InputDirectory -PathType Container)) { throw "Required directory not found: $InputDirectory" }
if (-not (Test-Path -LiteralPath $FontPath -PathType Leaf)) { throw "Required font not found: $FontPath" }
if ([string]::IsNullOrWhiteSpace($Text)) { throw 'OSD auto-mode text is empty.' }

Add-Type -AssemblyName System.Drawing
$files = @(Get-ChildItem -LiteralPath $InputDirectory -File | Where-Object {
    $_.Name -match '^KeyboardLightAuto_(Dark|Light)(@\d+)?\.png$'
} | Sort-Object Name)
if ($files.Count -eq 0) { throw 'No KeyboardLightAuto OSD images were found.' }

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$fonts = New-Object Drawing.Text.PrivateFontCollection
$fonts.AddFontFile($FontPath)
if ($fonts.Families.Count -ne 1) { throw "Unable to load the OSD font: $FontPath" }
$family = $fonts.Families[0]
$localized = 0
$skipped = 0
try {
    foreach ($file in $files) {
        try {
            $bitmap = New-Object Drawing.Bitmap($file.FullName)
            try {
                if ($bitmap.Width -ne $bitmap.Height -or $bitmap.Width -lt 160 -or $bitmap.Width -gt 800 -or
                    $bitmap.PixelFormat -ne [System.Drawing.Imaging.PixelFormat]::Format32bppArgb) {
                    throw "unsupported layout"
                }

                $width = [single]$bitmap.Width
                $height = [single]$bitmap.Height
                $background = $bitmap.GetPixel([int]($width / 2), [int]($height * 0.70))
                if ($background.A -ne 76) { throw "unexpected background alpha" }

                $graphics = [Drawing.Graphics]::FromImage($bitmap)
                try {
                    $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
                    $backgroundBrush = New-Object Drawing.SolidBrush($background)
                    try {
                        $graphics.FillRectangle($backgroundBrush, $width * 0.25, $height * 0.72, $width * 0.50, $height * 0.20)
                    } finally { $backgroundBrush.Dispose() }

                    $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
                    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
                    $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
                    $font = New-Object Drawing.Font($family, ($width * 0.10), [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel)
                    $foreground = if ($file.Name -match '_Dark') {
                        [Drawing.Color]::FromArgb(255, 255, 255, 255)
                    } else {
                        [Drawing.Color]::FromArgb(255, 17, 17, 17)
                    }
                    $textBrush = New-Object Drawing.SolidBrush($foreground)
                    $format = New-Object Drawing.StringFormat
                    try {
                        $format.Alignment = [Drawing.StringAlignment]::Center
                        $format.LineAlignment = [Drawing.StringAlignment]::Center
                        $format.FormatFlags = [Drawing.StringFormatFlags]::NoClip
                        $textRectangle = New-Object Drawing.RectangleF(0, ($height * 0.725), $width, $height * 0.1875)
                        $graphics.DrawString($Text, $font, $textBrush, $textRectangle, $format)
                    } finally {
                        $format.Dispose()
                        $textBrush.Dispose()
                        $font.Dispose()
                    }
                } finally { $graphics.Dispose() }

                $output = Join-Path $OutputDirectory $file.Name
                $bitmap.Save($output, [System.Drawing.Imaging.ImageFormat]::Png)
                $localized += 1
            } finally { $bitmap.Dispose() }
        } catch {
            $skipped += 1
            Write-Output "WARN: skipped OSD image $($file.Name): $($_.Exception.Message)"
        }
    }
} finally { $fonts.Dispose() }

if ($localized -eq 0) { throw 'No OSD image could be localized.' }
Write-Output "Localized $localized keyboard-backlight OSD image(s) ($skipped skipped): $OutputDirectory"
