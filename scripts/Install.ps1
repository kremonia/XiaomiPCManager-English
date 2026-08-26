# Turn-key English patch for Xiaomi PC Manager (any 5.8.x build).
# Patches are applied to the user's own installed files; every step degrades
# gracefully to a warning when the installed build differs from what the
# dictionaries were authored against.
#
# Native-layer technique adapted from yoursAnthony/XiaomiPCManager-Locale-Patch (MIT)
# - see THIRD_PARTY_NOTICES.md.
param(
    [string]$Language = 'en',
    [string]$AppDirectory,
    [switch]$NoLaunch,
    [switch]$Elevated
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

$updateMessage = 'A newer version is available. Reinstall the English patch after updating.'
$osdAutoText = 'Auto'
# Tray tooltip source text: 小米电脑管家 (built from char codes so this script
# is immune to PowerShell 5.1 reading a BOM-less file with the wrong codepage.)
$trayNameZh = -join @([char]0x5C0F, [char]0x7C73, [char]0x7535, [char]0x8111, [char]0x7BA1, [char]0x5BB6)
$trayPatch = @{ File = 'MiSmartShareDLL.dll'; Source = $trayNameZh; Replacement = 'Xiaomi' }
$tools = @{
    sdkPackage = 'Microsoft.Windows.SDK.BuildTools.10.0.26100.1742'
    sdkUrl     = 'https://www.nuget.org/api/v2/package/Microsoft.Windows.SDK.BuildTools/10.0.26100.1742'
    cecilPackage = 'Mono.Cecil.0.11.6'
    cecilUrl     = 'https://www.nuget.org/api/v2/package/Mono.Cecil/0.11.6'
}
$priFiles = @('resources.pri', 'PcControlCenter.pri', 'Microsoft.UI.Xaml.Controls.pri')
$priMaps = @{
    'resources.pri'                   = 'XiaomiPcManager'
    'PcControlCenter.pri'             = 'PcControlCenter'
    'Microsoft.UI.Xaml.Controls.pri'  = 'Microsoft.WindowsAppRuntime.1.4'
}
$webDictionary = Join-Path $repoRoot 'translations.json'
$priDictionary = Join-Path $repoRoot 'translations\pri-en.json'
$clipboardDictionary = Join-Path $repoRoot 'translations\clipboard-en.json'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    $arguments = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'),
        '-Language', $Language, '-Elevated', '-NoLaunch'
    )
    if ($AppDirectory) { $arguments += @('-AppDirectory', ('"' + $AppDirectory + '"')) }
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs -Wait -PassThru
    if ($process.ExitCode -eq 0 -and -not $NoLaunch) {
        $resolved = if ($AppDirectory) { $AppDirectory } else {
            $base = 'C:\Program Files\MI\XiaomiPCManager'
            $candidates = @(Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue |
                Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'XiaomiPcManager.exe') } |
                Sort-Object Name -Descending)
            if ($candidates.Count -eq 0) { throw "Xiaomi PC Manager was not found under $base" }
            $candidates[0].FullName
        }
        $osd = Join-Path $resolved 'OSDLauncher.exe'
        if (Test-Path -LiteralPath $osd -PathType Leaf) {
            Start-Process -FilePath $osd -WorkingDirectory $resolved -WindowStyle Hidden
        }
        Start-Process -FilePath (Join-Path $resolved 'XiaomiPcManager.exe') -WorkingDirectory $resolved
    }
    exit $process.ExitCode
}

# --- Locate the app (newest version folder by default) ---
if (-not $AppDirectory) {
    $base = 'C:\Program Files\MI\XiaomiPCManager'
    $candidates = @(Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'XiaomiPcManager.exe') } |
        Sort-Object Name -Descending)
    if ($candidates.Count -eq 0) { throw "Xiaomi PC Manager was not found under $base" }
    $AppDirectory = $candidates[0].FullName
}
if (-not (Test-Path -LiteralPath (Join-Path $AppDirectory 'XiaomiPcManager.exe') -PathType Leaf)) {
    throw "Xiaomi PC Manager was not found: $AppDirectory"
}
$appVersion = Split-Path -Leaf $AppDirectory
Write-Output "App: $AppDirectory"

# --- Collect the web bundles to patch ---
$webBundles = @()
$mainJs = Join-Path $AppDirectory 'dist\static\js\main.js'
if (Test-Path -LiteralPath $mainJs -PathType Leaf) { $webBundles += 'dist\static\js\main.js' }
else { Write-Output 'WARN: dist\static\js\main.js not found; main window stays as-is.' }
$searchDir = Join-Path $AppDirectory 'Search\dist\assets'
if (Test-Path -LiteralPath $searchDir -PathType Container) {
    $webBundles += @(Get-ChildItem -LiteralPath $searchDir -File -Filter '*.js' |
        ForEach-Object { 'Search\dist\assets\' + $_.Name })
} else {
    Write-Output 'WARN: Search\dist\assets not found; AI Search stays as-is.'
}

$osdImages = @()
$osdDir = Join-Path $AppDirectory 'res\Image'
if (Test-Path -LiteralPath $osdDir -PathType Container) {
    $osdImages = @(Get-ChildItem -LiteralPath $osdDir -File -Filter 'KeyboardLightAuto_*.png' |
        ForEach-Object { 'res\Image\' + $_.Name })
}

$targetFiles = @($webBundles) + $priFiles + @(
    'XiaomiPcManager.dll',
    $trayPatch.File,
    'PcClipboard\PcClipboard.exe'
) + $osdImages | Select-Object -Unique
$presentTargets = @($targetFiles | Where-Object { Test-Path -LiteralPath (Join-Path $AppDirectory $_) -PathType Leaf })

# --- Backups (state\<version>\original), migrating legacy .zh-CN.bak files ---
$stateRoot = Join-Path $repoRoot "state\$appVersion"
$backupRoot = Join-Path $stateRoot 'original'
New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
foreach ($relative in $presentTargets) {
    $backup = Join-Path $backupRoot $relative
    if (Test-Path -LiteralPath $backup -PathType Leaf) { continue }
    $installed = Join-Path $AppDirectory $relative
    $legacy = "$installed.zh-CN.bak"
    New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
    if (Test-Path -LiteralPath $legacy -PathType Leaf) {
        Copy-Item -LiteralPath $legacy -Destination $backup
    } else {
        Copy-Item -LiteralPath $installed -Destination $backup
    }
}
Write-Output "Originals backed up: $backupRoot"

# --- Stop the app ---
$processNames = @('XiaomiPcManager.exe', 'XiaomiPcHost.exe', 'PcClipboard.exe', 'OSDUtility.exe')
$processIds = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -in $processNames -and $_.ExecutablePath -and
        $_.ExecutablePath.StartsWith($AppDirectory, [StringComparison]::OrdinalIgnoreCase) } |
    Select-Object -ExpandProperty ProcessId)
foreach ($processId in $processIds) { Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue }
foreach ($processId in $processIds) { Wait-Process -Id $processId -Timeout 10 -ErrorAction SilentlyContinue }

# --- Download build tools (pinned NuGet packages, cached in .tools) ---
Add-Type -AssemblyName System.IO.Compression.FileSystem
$toolsRoot = Join-Path $repoRoot '.tools'
New-Item -ItemType Directory -Path $toolsRoot -Force | Out-Null
function Install-NugetTool([string]$PackageName, [string]$Url, [string]$RequiredRelativePath) {
    $destination = Join-Path $toolsRoot $PackageName
    $required = Join-Path $destination $RequiredRelativePath
    if (Test-Path -LiteralPath $required -PathType Leaf) { return $required }
    if (Test-Path -LiteralPath $destination) {
        Remove-Item -LiteralPath $destination -Recurse -Force
    }
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    $packageFile = Join-Path $toolsRoot "$PackageName.nupkg"
    Write-Output "Downloading $PackageName..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $Url -UseBasicParsing -OutFile $packageFile
    [IO.Compression.ZipFile]::ExtractToDirectory($packageFile, $destination)
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Tool package layout is unsupported: $required" }
    return $required
}
$makePri = Install-NugetTool $tools.sdkPackage $tools.sdkUrl 'bin\10.0.26100.0\x64\makepri.exe'
$cecil = Install-NugetTool $tools.cecilPackage $tools.cecilUrl 'lib\net40\Mono.Cecil.dll'

# --- Build every patched artifact from the pristine backups ---
$buildRoot = Join-Path $stateRoot 'build'
$workRoot = Join-Path $stateRoot 'work'
if (Test-Path -LiteralPath $buildRoot) { Remove-Item -LiteralPath $buildRoot -Recurse -Force }
if (Test-Path -LiteralPath $workRoot) { Remove-Item -LiteralPath $workRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $buildRoot, $workRoot | Out-Null
$builtFiles = @{}
$warnings = New-Object 'Collections.Generic.List[string]'
function Invoke-Step([string]$Name, [scriptblock]$Action) {
    try {
        & $Action
    } catch {
        $message = "${Name}: $($_.Exception.Message)"
        $warnings.Add($message)
        Write-Output "WARN: $message"
    }
}

foreach ($relative in $webBundles) {
    $source = Join-Path $backupRoot $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
    $output = Join-Path $buildRoot $relative
    Invoke-Step "web $relative" {
        & (Join-Path $PSScriptRoot 'Patch-Web.ps1') -InputBundle $source -OutputBundle $output `
            -TranslationPath $webDictionary
        $builtFiles[$relative] = $output
    }
}

$priConfig = Join-Path $PSScriptRoot 'priconfig.xml'
foreach ($priFile in $priFiles) {
    $source = Join-Path $backupRoot $priFile
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        $warnings.Add("pri $priFile not installed (file missing)")
        continue
    }
    $dump = Join-Path $workRoot "$priFile.xml"
    $localized = Join-Path $workRoot ([IO.Path]::GetFileNameWithoutExtension($priFile))
    $output = Join-Path $buildRoot $priFile
    Invoke-Step "pri $priFile" {
        & $makePri dump /if $source /of $dump /dt Detailed /o | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "MakePRI dump failed: $priFile" }
        & (Join-Path $PSScriptRoot 'Patch-Pri.ps1') -InputDump $dump -OutputDirectory $localized `
            -TranslationPath $priDictionary -PreferredCandidateLanguage 'EN-US'
        & $makePri new /pr $localized /cf $priConfig /in $priMaps[$priFile] /of $output /o | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "MakePRI build failed: $priFile" }
        $builtFiles[$priFile] = $output
    }
}

Invoke-Step 'assembly' {
    $output = & (Join-Path $PSScriptRoot 'Patch-Assembly.ps1') `
        -InputAssembly (Join-Path $backupRoot 'XiaomiPcManager.dll') `
        -OutputAssembly (Join-Path $buildRoot 'XiaomiPcManager.dll') `
        -CecilPath $cecil -UpdateMessage $updateMessage
    Write-Output $output
    $builtFiles['XiaomiPcManager.dll'] = (Join-Path $buildRoot 'XiaomiPcManager.dll')
}

Invoke-Step 'tray tooltip' {
    $output = & (Join-Path $PSScriptRoot 'Patch-NativeString.ps1') `
        -InputPath (Join-Path $backupRoot $trayPatch.File) `
        -OutputPath (Join-Path $buildRoot $trayPatch.File) `
        -SourceText $trayPatch.Source -ReplacementText $trayPatch.Replacement
    Write-Output $output
    $builtFiles[$trayPatch.File] = (Join-Path $buildRoot $trayPatch.File)
}

Invoke-Step 'clipboard' {
    $output = & (Join-Path $PSScriptRoot 'Patch-Clipboard.ps1') `
        -InputAssembly (Join-Path $backupRoot 'PcClipboard\PcClipboard.exe') `
        -OutputAssembly (Join-Path $buildRoot 'PcClipboard\PcClipboard.exe') `
        -TranslationPath $clipboardDictionary -CecilPath $cecil
    Write-Output $output
    $builtFiles['PcClipboard\PcClipboard.exe'] = (Join-Path $buildRoot 'PcClipboard\PcClipboard.exe')
}

$osdFont = Join-Path $AppDirectory 'Assets\font\MiSans-Medium.ttf'
Invoke-Step 'osd images' {
    & (Join-Path $PSScriptRoot 'Patch-OsdImages.ps1') `
        -InputDirectory (Join-Path $backupRoot 'res\Image') `
        -OutputDirectory (Join-Path $buildRoot 'res\Image') `
        -FontPath $osdFont -Text $osdAutoText
    Get-ChildItem -LiteralPath (Join-Path $buildRoot 'res\Image') -File |
        ForEach-Object { $builtFiles['res\Image\' + $_.Name] = $_.FullName }
}

if ($builtFiles.Count -eq 0) { throw 'No patch could be built for this app version.' }

# --- Install the built files ---
foreach ($relative in $builtFiles.Keys) {
    $target = Join-Path $AppDirectory $relative
    $temporary = "$target.xpm-new"
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath $builtFiles[$relative] -Destination $temporary -Force
    for ($attempt = 1; $attempt -le 10; $attempt++) {
        try {
            Move-Item -LiteralPath $temporary -Destination $target -Force
            break
        } catch {
            if ($attempt -eq 10) { throw }
            Start-Sleep -Milliseconds 500
        }
    }
    Write-Output "Installed: $relative"
}

$installedState = [ordered]@{
    appVersion   = $appVersion
    appDirectory = $AppDirectory
    installedUtc = [DateTime]::UtcNow.ToString('o')
    patchedFiles = @($builtFiles.Keys)
    warnings     = @($warnings)
}
[IO.File]::WriteAllText((Join-Path $stateRoot 'installed.json'),
    ($installedState | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))

if (-not $NoLaunch) {
    $osd = Join-Path $AppDirectory 'OSDLauncher.exe'
    if (Test-Path -LiteralPath $osd -PathType Leaf) {
        Start-Process -FilePath $osd -WorkingDirectory $AppDirectory -WindowStyle Hidden
    }
    Start-Process -FilePath (Join-Path $AppDirectory 'XiaomiPcManager.exe') -WorkingDirectory $AppDirectory
}
Write-Output ''
Write-Output "English patch installed ($($builtFiles.Count) file(s), $($warnings.Count) warning(s))."
exit 0
