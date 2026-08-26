# Adapted from yoursAnthony/XiaomiPCManager-Locale-Patch (MIT) - see THIRD_PARTY_NOTICES.md
# Changes: the update-dialog replacement is pattern-based (any <ShowUpdateWindow*> closure
# loading _updateChangeLogs) instead of a fixed compiler-generated closure index, and a
# missing pattern degrades to a warning so other patches still install on newer builds.
param(
    [Parameter(Mandatory = $true)][string]$InputAssembly,
    [Parameter(Mandatory = $true)][string]$OutputAssembly,
    [Parameter(Mandatory = $true)][string]$CecilPath,
    [Parameter(Mandatory = $true)][string]$UpdateMessage
)

$ErrorActionPreference = 'Stop'
foreach ($path in $InputAssembly, $CecilPath) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required file not found: $path" }
}

[void][Reflection.Assembly]::LoadFrom($CecilPath)
$resolver = New-Object Mono.Cecil.DefaultAssemblyResolver
$resolver.AddSearchDirectory((Split-Path -Parent $InputAssembly))
$reader = New-Object Mono.Cecil.ReaderParameters
$reader.AssemblyResolver = $resolver
$reader.InMemory = $true
$assembly = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($InputAssembly, $reader)
try {
    $program = $assembly.MainModule.GetType('XiaomiPcManager.Program')
    $main = $null
    if ($program) {
        $main = $program.Methods | Where-Object { $_.Name -eq 'Main' -and $_.Parameters.Count -eq 1 } | Select-Object -First 1
    }
    if (-not $main -or -not $main.HasBody) { throw 'XiaomiPcManager.Program.Main was not found.' }
    if ($main.Body.Instructions | Where-Object { $_.Operand -and $_.Operand.Name -eq 'SetThreadUILanguage' }) {
        throw 'The input assembly is already patched.'
    }

    $kernel32 = $assembly.MainModule.ModuleReferences | Where-Object { $_.Name -ieq 'kernel32.dll' } | Select-Object -First 1
    if (-not $kernel32) {
        $kernel32 = New-Object Mono.Cecil.ModuleReference -ArgumentList 'kernel32.dll'
        [void]$assembly.MainModule.ModuleReferences.Add($kernel32)
    }
    $methodAttributes = [Mono.Cecil.MethodAttributes](
        [int][Mono.Cecil.MethodAttributes]::Private -bor
        [int][Mono.Cecil.MethodAttributes]::Static -bor
        [int][Mono.Cecil.MethodAttributes]::HideBySig -bor
        [int][Mono.Cecil.MethodAttributes]::PInvokeImpl
    )
    $setter = New-Object Mono.Cecil.MethodDefinition -ArgumentList @(
        'SetThreadUILanguage', $methodAttributes, $assembly.MainModule.TypeSystem.UInt16
    )
    [void]$setter.Parameters.Add((New-Object Mono.Cecil.ParameterDefinition -ArgumentList @(
        'langId', [Mono.Cecil.ParameterAttributes]::None, $assembly.MainModule.TypeSystem.UInt16
    )))
    $pinvokeAttributes = [Mono.Cecil.PInvokeAttributes](
        [int][Mono.Cecil.PInvokeAttributes]::NoMangle -bor
        [int][Mono.Cecil.PInvokeAttributes]::CallConvWinapi
    )
    $setter.PInvokeInfo = New-Object Mono.Cecil.PInvokeInfo -ArgumentList (
        $pinvokeAttributes, 'SetThreadUILanguage', $kernel32
    )
    $setter.ImplAttributes = [Mono.Cecil.MethodImplAttributes]::PreserveSig
    [void]$program.Methods.Add($setter)

    # Force the process to resolve Xiaomi's complete zh-CN resource graph.
    # Only strings inside that graph are replaced by Patch-Pri.ps1.
    $processor = $main.Body.GetILProcessor()
    $first = $main.Body.Instructions[0]
    $processor.InsertBefore($first, $processor.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4, 0x0804))
    $processor.InsertBefore($first, $processor.Create([Mono.Cecil.Cil.OpCodes]::Call, $setter))
    $processor.InsertBefore($first, $processor.Create([Mono.Cecil.Cil.OpCodes]::Pop))

    # The updater's change log is decoded as question marks outside Chinese Windows.
    # Replace the changelog loads inside every update-display closure with a localized warning.
    $ota = $assembly.MainModule.GetType('XiaomiPcManager.Services.OTAService')
    $patchedDialogs = 0
    if ($ota) {
        foreach ($method in @($ota.Methods)) {
            if (-not $method.HasBody -or $method.Name -notlike '<ShowUpdateWindow*') { continue }
            foreach ($instruction in @($method.Body.Instructions)) {
                if ($instruction.OpCode.Code -ne [Mono.Cecil.Cil.Code]::Ldfld -or
                    -not $instruction.Operand -or $instruction.Operand.Name -ne '_updateChangeLogs') { continue }
                if (-not $instruction.Previous -or
                    $instruction.Previous.OpCode.Code -ne [Mono.Cecil.Cil.Code]::Ldarg_0) { continue }
                $instruction.Previous.OpCode = [Mono.Cecil.Cil.OpCodes]::Nop
                $instruction.Previous.Operand = $null
                $instruction.OpCode = [Mono.Cecil.Cil.OpCodes]::Ldstr
                $instruction.Operand = $UpdateMessage
                $patchedDialogs += 1
            }
        }
    }
    if ($patchedDialogs -eq 0) {
        Write-Output 'WARN: no update-dialog changelog load found; update windows keep their original behavior.'
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $OutputAssembly) -Force | Out-Null
    $assembly.Write($OutputAssembly)
} finally {
    $assembly.Dispose()
    $resolver.Dispose()
}

$written = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($OutputAssembly)
try {
    $writtenMain = $written.MainModule.GetType('XiaomiPcManager.Program').Methods |
        Where-Object { $_.Name -eq 'Main' -and $_.Parameters.Count -eq 1 } | Select-Object -First 1
    $firstThree = @($writtenMain.Body.Instructions | Select-Object -First 3)
    if ($firstThree.Count -ne 3 -or $firstThree[0].OpCode.Code -ne [Mono.Cecil.Cil.Code]::Ldc_I4 -or
        [int]$firstThree[0].Operand -ne 0x0804 -or $firstThree[1].OpCode.Code -ne [Mono.Cecil.Cil.Code]::Call -or
        $firstThree[2].OpCode.Code -ne [Mono.Cecil.Cil.Code]::Pop) {
        throw 'Post-write verification of the locale patch failed.'
    }
} finally { $written.Dispose() }

Write-Output "Patched assembly ($patchedDialogs update dialog(s)): $OutputAssembly"
