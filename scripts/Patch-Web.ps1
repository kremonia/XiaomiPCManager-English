# Applies the flat zh->en dictionary to a WebView bundle by replacing WHOLE
# string literals (raw CJK or \uXXXX-escaped) via a proper JS tokenizer.
# Literals that are not dictionary keys (region data, calendar names, regex
# sources, ...) stay untouched - substring replacement corrupts such data.
param(
    [Parameter(Mandatory = $true)][string]$InputBundle,
    [Parameter(Mandatory = $true)][string]$OutputBundle,
    [Parameter(Mandatory = $true)][string]$TranslationPath
)

$ErrorActionPreference = 'Stop'
foreach ($path in $InputBundle, $TranslationPath) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required file not found: $path" }
}

Add-Type -Path (Join-Path $PSScriptRoot 'WebBundlePatcher.cs') `
    -ReferencedAssemblies System.Web.Extensions

$bytes = [IO.File]::ReadAllBytes($InputBundle)
$hadBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
$text = [Text.Encoding]::UTF8.GetString($bytes)
if ($hadBom) { $text = $text.Substring(1) }

$jsonDictionary = [IO.File]::ReadAllText($TranslationPath, [Text.Encoding]::UTF8)
$applied = 0
$keptChinese = 0
$patched = [WebBundlePatcher]::Patch($text, $jsonDictionary, [ref]$applied, [ref]$keptChinese)

$outputBytes = if ($hadBom) {
    [byte[]](0xEF, 0xBB, 0xBF) + [Text.Encoding]::UTF8.GetBytes($patched)
} else {
    [Text.Encoding]::UTF8.GetBytes($patched)
}
New-Item -ItemType Directory -Path (Split-Path -Parent $OutputBundle) -Force | Out-Null
[IO.File]::WriteAllBytes($OutputBundle, $outputBytes)

Write-Output ("Web bundle: {0} literal(s) translated, {1} Chinese literal(s) kept as-is: {2}" -f `
    $applied, $keptChinese, (Split-Path -Leaf $OutputBundle))
