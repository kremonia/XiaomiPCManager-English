# Adapted from yoursAnthony/XiaomiPCManager-Locale-Patch (MIT) - see THIRD_PARTY_NOTICES.md
# Changes: untranslated zh-CN candidates are kept as-is (counted) instead of aborting,
# so the patch works on app versions the dictionary has not seen yet.
param(
    [Parameter(Mandatory = $true)][string]$InputDump,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [Parameter(Mandatory = $true)][string]$TranslationPath,
    [Parameter(Mandatory = $true)][string]$PreferredCandidateLanguage
)

$ErrorActionPreference = 'Stop'
foreach ($path in $InputDump, $TranslationPath) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required file not found: $path" }
}

$translationRows = Get-Content -LiteralPath $TranslationPath -Raw -Encoding UTF8 | ConvertFrom-Json
$dictionary = @{}
foreach ($row in @($translationRows | ForEach-Object { $_ })) {
    $dictionary[[string]$row.Source] = [string]$row.Translation
}

[xml]$document = [IO.File]::ReadAllText($InputDump, [Text.Encoding]::UTF8)
$changed = 0
$missed = 0
$missedSamples = New-Object 'Collections.Generic.List[string]'
foreach ($resource in $document.SelectNodes('//NamedResource')) {
    $zh = $resource.SelectSingleNode('./Candidate[@type="String"][QualifierSet/Qualifier[@name="Language" and @value="ZH-CN"]]')
    if (-not $zh) { continue }
    $preferred = $resource.SelectSingleNode("./Candidate[@type='String'][QualifierSet/Qualifier[@name='Language' and @value='$PreferredCandidateLanguage']]")
    if ($preferred) {
        $zh.Value = [string]$preferred.Value
        $changed += 1
        continue
    }
    $source = [string]$zh.Value
    if ($dictionary.ContainsKey($source)) {
        $zh.Value = [string]$dictionary[$source]
        $changed += 1
    } else {
        $missed += 1
        if ($missedSamples.Count -lt 8) { [void]$missedSamples.Add($source) }
    }
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$outputPath = Join-Path $OutputDirectory 'resources.pri.xml'
$settings = New-Object Xml.XmlWriterSettings
$settings.Encoding = New-Object Text.UTF8Encoding($false)
$settings.Indent = $true
$settings.NewLineHandling = [Xml.NewLineHandling]::None
$writer = [Xml.XmlWriter]::Create($outputPath, $settings)
try { $document.Save($writer) } finally { $writer.Dispose() }
if ($missed -gt 0) {
    Write-Output ("WARN: {0} zh-CN string(s) have no translation and stay Chinese: {1}" -f $missed, ($missedSamples -join ' | '))
}
Write-Output "Patched $changed zh-CN string candidates: $outputPath"
