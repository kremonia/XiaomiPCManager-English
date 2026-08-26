# Adapted from yoursAnthony/XiaomiPCManager-Locale-Patch (MIT) - see THIRD_PARTY_NOTICES.md
# Changes: partial matches are allowed - entries the installed build does not contain are
# skipped with a warning instead of aborting, so the patch degrades gracefully on new versions.
param(
    [Parameter(Mandatory = $true)][string]$InputAssembly,
    [Parameter(Mandatory = $true)][string]$OutputAssembly,
    [Parameter(Mandatory = $true)][string]$TranslationPath,
    [Parameter(Mandatory = $true)][string]$CecilPath
)

$ErrorActionPreference = 'Stop'
foreach ($path in $InputAssembly, $TranslationPath, $CecilPath) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required file not found: $path" }
}

$translation = Get-Content -LiteralPath $TranslationPath -Raw -Encoding UTF8 | ConvertFrom-Json
$resourceTranslations = @($translation.resources.PSObject.Properties)
$ilTranslations = @($translation.ilStrings.PSObject.Properties)
if ($resourceTranslations.Count -eq 0 -and $ilTranslations.Count -eq 0) {
    throw "Clipboard translations are empty: $TranslationPath"
}

[void][Reflection.Assembly]::LoadFrom($CecilPath)
$resolver = New-Object Mono.Cecil.DefaultAssemblyResolver
$resolver.AddSearchDirectory((Split-Path -Parent $InputAssembly))
$readerParameters = New-Object Mono.Cecil.ReaderParameters
$readerParameters.AssemblyResolver = $resolver
$readerParameters.InMemory = $true
$assembly = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($InputAssembly, $readerParameters)
try {
    if ($assembly.Name.Name -ne 'PcClipboard') { throw "Unsupported clipboard assembly: $($assembly.Name.Name)" }

    $resourceName = 'PcClipboard.Properties.Resources.resources'
    $resource = $assembly.MainModule.Resources | Where-Object { $_.Name -eq $resourceName } | Select-Object -First 1
    if (-not $resource -or $resource.ResourceType -ne [Mono.Cecil.ResourceType]::Embedded) {
        throw "Embedded clipboard resource was not found: $resourceName"
    }

    $sourceStream = $resource.GetResourceStream()
    $resourceReader = New-Object Resources.ResourceReader($sourceStream)
    $outputStream = New-Object IO.MemoryStream
    $resourceWriter = New-Object Resources.ResourceWriter($outputStream)
    $patchedResourceKeys = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $skippedKeys = New-Object 'Collections.Generic.List[string]'
    try {
        $enumerator = $resourceReader.GetEnumerator()
        while ($enumerator.MoveNext()) {
            $key = [string]$enumerator.Key
            $value = $enumerator.Value
            $entry = $resourceTranslations | Where-Object { $_.Name -ceq $key } | Select-Object -First 1
            if ($entry) {
                if ($value -isnot [string] -or [string]$value -cne [string]$entry.Value.source) {
                    [void]$skippedKeys.Add($key)
                    $resourceWriter.AddResource($key, $value)
                } else {
                    $resourceWriter.AddResource($key, [string]$entry.Value.value)
                    [void]$patchedResourceKeys.Add($key)
                }
            } else {
                $resourceWriter.AddResource($key, $value)
            }
        }
        $resourceWriter.Generate()
        $resourceBytes = $outputStream.ToArray()
    } finally {
        $resourceWriter.Dispose()
        $outputStream.Dispose()
        $resourceReader.Dispose()
        $sourceStream.Dispose()
    }
    if ($skippedKeys.Count -gt 0) {
        Write-Output ("WARN: clipboard resources with changed source text were left as-is: " + ($skippedKeys -join ', '))
    }
    if ($patchedResourceKeys.Count -eq 0 -and $resourceTranslations.Count -gt 0) {
        Write-Output 'WARN: no clipboard resources matched this build.'
    }

    $resourceIndex = $assembly.MainModule.Resources.IndexOf($resource)
    $localizedResource = New-Object Mono.Cecil.EmbeddedResource -ArgumentList @(
        $resource.Name, $resource.Attributes, [byte[]]$resourceBytes
    )
    $assembly.MainModule.Resources[$resourceIndex] = $localizedResource

    $ilCounts = @{}
    foreach ($entry in $ilTranslations) { $ilCounts[$entry.Name] = 0 }
    $typeStack = New-Object 'Collections.Generic.Stack[Mono.Cecil.TypeDefinition]'
    foreach ($type in $assembly.MainModule.Types) { $typeStack.Push($type) }
    while ($typeStack.Count -gt 0) {
        $type = $typeStack.Pop()
        foreach ($nested in $type.NestedTypes) { $typeStack.Push($nested) }
        foreach ($method in $type.Methods) {
            if (-not $method.HasBody) { continue }
            foreach ($instruction in $method.Body.Instructions) {
                if ($instruction.OpCode.Code -ne [Mono.Cecil.Cil.Code]::Ldstr) { continue }
                $source = [string]$instruction.Operand
                if (-not $ilCounts.ContainsKey($source)) { continue }
                $instruction.Operand = [string]$ilTranslations.Where({ $_.Name -ceq $source }, 'First').Value
                $ilCounts[$source] += 1
            }
        }
    }
    $missingIl = @($ilCounts.GetEnumerator() | Where-Object Value -eq 0 | ForEach-Object Key)
    if ($missingIl.Count -gt 0) {
        Write-Output ("WARN: clipboard IL strings not present in this build: " + ($missingIl -join ', '))
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $OutputAssembly) -Force | Out-Null
    $assembly.Write($OutputAssembly)
} finally {
    $assembly.Dispose()
    $resolver.Dispose()
}

$ilPatched = ($ilCounts.Values | Measure-Object -Sum).Sum
if ($ilPatched -eq 0 -and $patchedResourceKeys.Count -eq 0) {
    throw 'This build contains none of the known clipboard strings.'
}
Write-Output "Patched $($patchedResourceKeys.Count) clipboard resource(s) and $ilPatched IL string(s): $OutputAssembly"
