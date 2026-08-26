# Swaps Chinese OSD artwork for Xiaomi's own English artwork.
#
# Every OSD icon family ships three variants: unsuffixed Name.png (English
# art), Name_Dark.png / Name_Light.png (Chinese art, theme variants, plus
# @scale sizes), and for the Workload families Name_En_Dark.png /
# Name_En_Light.png (English theme art). The app resolves its UI language to
# zh-CN (forced by the assembly patch), so it loads the _Dark/_Light Chinese
# files; copying the English art over them localizes every OSD without any
# redrawing.
param(
    [Parameter(Mandatory = $true)][string]$InputDirectory,
    [Parameter(Mandatory = $true)][string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $InputDirectory -PathType Container)) {
    throw "Required directory not found: $InputDirectory"
}

$files = @(Get-ChildItem -LiteralPath $InputDirectory -File |
    Where-Object { $_.Name -match '^(.+?)_(Dark|Light)(@\d+)?\.png$' })
if ($files.Count -eq 0) { throw 'No themed OSD images were found.' }

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$swapped = 0
$skipped = New-Object 'Collections.Generic.List[string]'
foreach ($file in $files) {
    if ($file.Name -notmatch '^(.+?)_(Dark|Light)(@\d+)?\.png$') { continue }
    $base = $Matches[1]
    $theme = $Matches[2]
    $scale = $Matches[3]
    if ($base -like '*_En') { continue }              # already English art
    $enSibling = Join-Path $InputDirectory ($base + '_En_' + $theme + $scale + '.png')
    $enPlain = Join-Path $InputDirectory ($base + '.png')
    $source = if (Test-Path -LiteralPath $enSibling -PathType Leaf) { $enSibling }
    elseif (Test-Path -LiteralPath $enPlain -PathType Leaf) { $enPlain }
    else { $null }
    if (-not $source) {
        [void]$skipped.Add($file.Name)
        continue
    }
    Copy-Item -LiteralPath $source -Destination (Join-Path $OutputDirectory $file.Name) -Force
    $swapped += 1
}

if ($swapped -eq 0) { throw 'No OSD image could be swapped to English artwork.' }
if ($skipped.Count -gt 0) {
    Write-Output ("WARN: {0} themed OSD image(s) have no English artwork and stay Chinese, e.g.: {1}" -f `
        $skipped.Count, (($skipped | Select-Object -First 8) -join ', '))
}
Write-Output "Swapped $swapped themed OSD image(s) to Xiaomi's English artwork: $OutputDirectory"
