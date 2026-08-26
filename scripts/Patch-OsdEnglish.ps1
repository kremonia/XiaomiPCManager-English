# Localizes themed OSD icons (Name_Dark/_Light + @scale variants, square
# canvases with a Chinese label baked into the bottom band).
#
# Two strategies per family:
#   1. Families with genuine Name_En_Dark/_En_Light siblings (the Workload
#      set): the English sibling is copied over - same canvas, same scales.
#   2. Every other family in the label map: the original Chinese label band
#      is erased and the English label is drawn, auto-fitted to the band.
#
# The unsuffixed Name.png files are Xiaomi's English art in a DIFFERENT
# (portrait, unscaled) design - useful as the label source of truth, but they
# must never be copied into the themed slots (wrong geometry).
param(
    [Parameter(Mandatory = $true)][string]$InputDirectory,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [Parameter(Mandatory = $true)][string]$FontPath
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $InputDirectory -PathType Container)) {
    throw "Required directory not found: $InputDirectory"
}
if (-not (Test-Path -LiteralPath $FontPath -PathType Leaf)) { throw "Required font not found: $FontPath" }

# English labels follow Xiaomi's own unsuffixed artwork ("Brightness 5",
# "Mic on", "120Hz", "Auto").
$labelMap = @{
    'KeyboardLightAuto'  = 'Auto'
    'MuteOn'             = 'Mic on'
    'MuteOff'            = 'Mic off'
    'MicEarPhoneSocketWrong' = 'Mic jack'
    'NewQuietMode'       = 'Quiet'
    'NewSpeedMode'       = 'Speed'
    'NewIntelligentMode' = 'Smart'
    'NewLongBatteryMode' = 'Endurance'
    'NewDecepticonMode'  = 'Beast'
    'TurboBalance'       = 'Balance'
    'TurboSilent'        = 'Silent'
    'WorkloadNewDecepticon' = 'Beast'
    'WorkloadNewIntelligent' = 'Smart'
    'WorkloadNewLongBatteryLife' = 'Endurance'
    'DisFreErr'          = 'N/A'
    'DisFreErrAuto'      = 'Auto'
}
foreach ($level in 0..10) { $labelMap["KeyboardLight$level"] = "Brightness $level" }
foreach ($hz in 48, 60, 72, 90, 120, 144, 165, 240) { $labelMap["DisFre$hz"] = "${hz}Hz" }

Add-Type -AssemblyName System.Drawing
$files = @(Get-ChildItem -LiteralPath $InputDirectory -File |
    Where-Object { $_.Name -match '^(.+?)_(Dark|Light)(@\d+)?\.png$' })
if ($files.Count -eq 0) { throw 'No themed OSD images were found.' }

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$fonts = New-Object Drawing.Text.PrivateFontCollection
$fonts.AddFontFile($FontPath)
if ($fonts.Families.Count -lt 1) { throw "Unable to load the OSD font: $FontPath" }
$family = $fonts.Families[0]
$swapped = 0
$redrawn = 0
$skipped = New-Object 'Collections.Generic.List[string]'
try {
    foreach ($file in $files) {
        if ($file.Name -notmatch '^(.+?)_(Dark|Light)(@\d+)?\.png$') { continue }
        $base = $Matches[1]
        $theme = $Matches[2]
        $scale = $Matches[3]
        if ($base -like '*_En') { continue }

        $enSibling = Join-Path $InputDirectory ($base + '_En_' + $theme + $scale + '.png')
        $output = Join-Path $OutputDirectory $file.Name
        if (Test-Path -LiteralPath $enSibling -PathType Leaf) {
            Copy-Item -LiteralPath $enSibling -Destination $output -Force
            $swapped += 1
            continue
        }
        if (-not $labelMap.ContainsKey($base)) {
            [void]$skipped.Add($file.Name)
            continue
        }

        $text = [string]$labelMap[$base]
        $bitmap = New-Object Drawing.Bitmap($file.FullName)
        try {
            $width = [single]$bitmap.Width
            $height = [single]$bitmap.Height
            if ($bitmap.Width -ne $bitmap.Height -or $bitmap.Width -lt 160 -or $bitmap.Width -gt 800 -or
                $bitmap.PixelFormat -ne [System.Drawing.Imaging.PixelFormat]::Format32bppArgb) {
                throw "unsupported layout"
            }
            # Label backdrop: translucent panel under the glyph area.
            $background = $bitmap.GetPixel([int]($width / 2), [int]($height * 0.70))
            $foreground = if ($theme -eq 'Dark') {
                [Drawing.Color]::FromArgb(255, 255, 255, 255)
            } else {
                [Drawing.Color]::FromArgb(255, 17, 17, 17)
            }

            $graphics = [Drawing.Graphics]::FromImage($bitmap)
            try {
                $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
                $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

                # Fit the (longer English) label into the label zone.
                $fontSize = $width * 0.10
                $font = New-Object Drawing.Font($family, $fontSize, [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel)
                try {
                    $format = New-Object Drawing.StringFormat
                    try {
                        $format.Alignment = [Drawing.StringAlignment]::Center
                        $format.LineAlignment = [Drawing.StringAlignment]::Center
                        $format.FormatFlags = [Drawing.StringFormatFlags]::NoClip
                        $maxWidth = $width * 0.80
                        $measured = $graphics.MeasureString($text, $font, [int]$maxWidth, $format)
                        while ($measured.Width -gt $maxWidth -and $fontSize -gt $width * 0.05) {
                            $fontSize -= $width * 0.005
                            $font.Dispose()
                            $font = New-Object Drawing.Font($family, $fontSize, [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel)
                            $measured = $graphics.MeasureString($text, $font, [int]$maxWidth, $format)
                        }

                        # Erase the Chinese label plus whatever the English
                        # text needs, staying inside the label zone.
                        $eraseX = [Math]::Min($width * 0.25, ($width - $measured.Width) / 2 - $width * 0.02)
                        $eraseX = [Math]::Max($width * 0.05, $eraseX)
                        $eraseW = [Math]::Min($width * 0.90, $width - 2 * $eraseX)
                        $eraseY = $height * 0.715
                        $eraseH = $height * 0.21
                        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
                        $backgroundBrush = New-Object Drawing.SolidBrush($background)
                        try { $graphics.FillRectangle($backgroundBrush, $eraseX, $eraseY, $eraseW, $eraseH) }
                        finally { $backgroundBrush.Dispose() }

                        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
                        $textBrush = New-Object Drawing.SolidBrush($foreground)
                        try {
                            $textRectangle = New-Object Drawing.RectangleF(0, ($height * 0.715), $width, $height * 0.21)
                            $graphics.DrawString($text, $font, $textBrush, $textRectangle, $format)
                        } finally { $textBrush.Dispose() }
                    } finally { $format.Dispose() }
                } finally { $font.Dispose() }
            } finally { $graphics.Dispose() }
            $bitmap.Save($output, [System.Drawing.Imaging.ImageFormat]::Png)
            $redrawn += 1
        } catch {
            [void]$skipped.Add($file.Name)
            Write-Output "WARN: skipped OSD image $($file.Name): $($_.Exception.Message)"
        } finally { $bitmap.Dispose() }
    }
} finally { $fonts.Dispose() }

if ($swapped -eq 0 -and $redrawn -eq 0) { throw 'No OSD image could be localized.' }
if ($skipped.Count -gt 0) {
    Write-Output ("WARN: {0} themed OSD image(s) skipped, e.g.: {1}" -f `
        $skipped.Count, (($skipped | Select-Object -First 8) -join ', '))
}
Write-Output "OSD images: $swapped swapped to English siblings, $redrawn redrawn with English labels: $OutputDirectory"
