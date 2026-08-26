# Adapted from yoursAnthony/XiaomiPCManager-Locale-Patch (MIT) - see THIRD_PARTY_NOTICES.md
# Changes: every occurrence is replaced (minimum one required); callers treat a missing
# string as a warning so other patches still install on newer builds.
param(
    [Parameter(Mandatory = $true)][string]$InputPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][string]$SourceText,
    [Parameter(Mandatory = $true)][string]$ReplacementText
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) { throw "Required file not found: $InputPath" }

$sourceBytes = [Text.Encoding]::Unicode.GetBytes($SourceText)
$replacementBytes = [Text.Encoding]::Unicode.GetBytes($ReplacementText)
if ($sourceBytes.Length -ne $replacementBytes.Length) {
    throw "Native UTF-16 replacement must have exactly $($sourceBytes.Length) bytes; received $($replacementBytes.Length)."
}

$bytes = [IO.File]::ReadAllBytes($InputPath)
$occurrences = 0
for ($offset = 0; $offset -le $bytes.Length - $sourceBytes.Length; $offset++) {
    $matches = $true
    for ($index = 0; $index -lt $sourceBytes.Length; $index++) {
        if ($bytes[$offset + $index] -ne $sourceBytes[$index]) { $matches = $false; break }
    }
    if (-not $matches) { continue }
    [Array]::Copy($replacementBytes, 0, $bytes, $offset, $replacementBytes.Length)
    $occurrences += 1
    $offset += $sourceBytes.Length - 1
}
if ($occurrences -lt 1) {
    throw "Native string '$SourceText' was not found in $InputPath"
}

New-Item -ItemType Directory -Path (Split-Path -Parent $OutputPath) -Force | Out-Null
[IO.File]::WriteAllBytes($OutputPath, $bytes)
Write-Output "Patched $occurrences native occurrence(s) of '$SourceText': $OutputPath"
