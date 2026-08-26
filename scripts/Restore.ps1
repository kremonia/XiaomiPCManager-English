# Restores the original Chinese files from the state backups (and legacy
# .zh-CN.bak files created by older versions of this patch).
param(
    [string]$AppDirectory,
    [switch]$NoLaunch,
    [switch]$Elevated
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    $arguments = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'),
        '-Elevated', '-NoLaunch'
    )
    if ($AppDirectory) { $arguments += @('-AppDirectory', ('"' + $AppDirectory + '"')) }
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs -Wait -PassThru
    exit $process.ExitCode
}

if (-not $AppDirectory) {
    $base = 'C:\Program Files\MI\XiaomiPCManager'
    $candidates = @(Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'XiaomiPcManager.exe') } |
        Sort-Object Name -Descending)
    if ($candidates.Count -eq 0) { throw "Xiaomi PC Manager was not found under $base" }
    $AppDirectory = $candidates[0].FullName
}
$appVersion = Split-Path -Leaf $AppDirectory
Write-Output "App: $AppDirectory"

$processNames = @('XiaomiPcManager.exe', 'XiaomiPcHost.exe', 'PcClipboard.exe', 'OSDUtility.exe')
$processIds = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -in $processNames -and $_.ExecutablePath -and
        $_.ExecutablePath.StartsWith($AppDirectory, [StringComparison]::OrdinalIgnoreCase) } |
    Select-Object -ExpandProperty ProcessId)
foreach ($processId in $processIds) { Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue }
foreach ($processId in $processIds) { Wait-Process -Id $processId -Timeout 10 -ErrorAction SilentlyContinue }

$restored = 0

# State backups (current format)
$backupRoot = Join-Path $repoRoot "state\$appVersion\original"
if (Test-Path -LiteralPath $backupRoot -PathType Container) {
    Get-ChildItem -LiteralPath $backupRoot -Recurse -File | ForEach-Object {
        $relative = $_.FullName.Substring($backupRoot.Length + 1)
        $target = Join-Path $AppDirectory $relative
        Copy-Item -LiteralPath $_.FullName -Destination $target -Force
        $restored += 1
        Write-Output "Restored: $relative"
    }
}

# Legacy .zh-CN.bak files (older versions of this patch)
Get-ChildItem -LiteralPath $AppDirectory -Recurse -File -Filter '*.zh-CN.bak' -ErrorAction SilentlyContinue |
    ForEach-Object {
        $target = $_.FullName.Substring(0, $_.FullName.Length - '.zh-CN.bak'.Length)
        Copy-Item -LiteralPath $_.FullName -Destination $target -Force
        $restored += 1
        Write-Output "Restored: $($_.Name -replace '\.zh-CN\.bak$', '')"
    }

if ($restored -eq 0) { Write-Output 'Nothing to restore (no backups found).' }
else { Write-Output "$restored file(s) restored to the original Chinese versions." }

if (-not $NoLaunch) {
    Start-Process -FilePath (Join-Path $AppDirectory 'XiaomiPcManager.exe') -WorkingDirectory $AppDirectory
}
exit 0
