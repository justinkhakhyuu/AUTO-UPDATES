param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('brutal', 'lite')]
    [string]$Channel,

    [Parameter(Mandatory = $true)]
    [string]$Version,

    [Parameter(Mandatory = $true)]
    [string]$ClientDll,

    [string]$NativeLib,

    [switch]$SkipPush
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$Text, [string]$Color = 'Cyan') {
    Write-Host $Text -ForegroundColor $Color
}

function Test-VersionString([string]$Value) {
    return [System.Version]::TryParse($Value.Trim(), [ref][System.Version]$null)
}

function Get-ManifestVersion([string]$ManifestPath, [string]$ChannelName) {
    if (-not (Test-Path $ManifestPath)) {
        return $null
    }

    $data = Get-Content $ManifestPath -Raw | ConvertFrom-Json
    return [string]$data.$ChannelName
}

function Test-VersionAllowed([string]$Current, [string]$New) {
    if ([string]::IsNullOrWhiteSpace($Current)) {
        return [pscustomobject]@{ Ok = $true }
    }

    if (-not (Test-VersionString $New)) {
        return [pscustomobject]@{
            Ok = $false
            Message = "Invalid version '$New'. Use format like 1.0.3"
        }
    }

    $currentVersion = [Version]$Current.Trim()
    $newVersion = [Version]$New.Trim()

    if ($newVersion -eq $currentVersion) {
        return [pscustomobject]@{
            Ok = $false
            Message = "Already on version $Current for '$Channel'. Use a higher version (e.g. $([Version]::new($currentVersion.Major, $currentVersion.Minor, $currentVersion.Build + 1)))."
        }
    }

    if ($newVersion -lt $currentVersion) {
        return [pscustomobject]@{
            Ok = $false
            Message = "Version $New is lower than current $Current. Please upgrade - use a version above $Current."
        }
    }

    return [pscustomobject]@{ Ok = $true }
}

$repo = Split-Path $PSScriptRoot -Parent
$manifestPath = Join-Path $repo 'updates\manifest.json'

if (-not (Test-Path $manifestPath)) {
    Write-Error "Manifest not found: $manifestPath"
}

if (-not (Test-VersionString $Version)) {
    Write-Host ""
    Write-Host "  Invalid version '$Version'. Use format like 1.0.3" -ForegroundColor Red
    Write-Host ""
    exit 1
}

$currentVersion = Get-ManifestVersion $manifestPath $Channel
$check = Test-VersionAllowed $currentVersion $Version
if (-not $check.Ok) {
    Write-Host ""
    Write-Host "  $($check.Message)" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

if (-not (Test-Path $ClientDll)) {
    Write-Error "Client.dll not found: $ClientDll`nBuild the project first (Compile.bat)."
}

# Real Client.dll is ~40MB+. Reject placeholder / text fakes.
$MinClientBytes = 5MB
$clientInfo = Get-Item $ClientDll
if ($clientInfo.Length -lt $MinClientBytes) {
    Write-Host ""
    Write-Host "  Client.dll is too small ($([math]::Round($clientInfo.Length / 1KB, 1)) KB)." -ForegroundColor Red
    Write-Host "  Expected a real build (~40+ MB). Run Compile.bat first." -ForegroundColor Yellow
    Write-Host "  Path: $ClientDll" -ForegroundColor DarkGray
    Write-Host ""
    exit 1
}

if ($Channel -eq 'brutal') {
    if ([string]::IsNullOrWhiteSpace($NativeLib)) {
        Write-Error "Brutal update needs -NativeLib path to libTERMINALX999Cheats.so"
    }

    if (-not (Test-Path $NativeLib)) {
        Write-Error "Native lib not found: $NativeLib`nBuild/sync native libs first."
    }

    $nativeInfo = Get-Item $NativeLib
    if ($nativeInfo.Length -lt 50KB) {
        Write-Host ""
        Write-Host "  libTERMINALX999Cheats.so is too small ($([math]::Round($nativeInfo.Length / 1KB, 1)) KB)." -ForegroundColor Red
        Write-Host "  Build/sync the real native lib first." -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }
}

Write-Host ""
Write-Step "  Black Corps - publish $Channel update"
Write-Host ""
Write-Host "  Current : $(if ($currentVersion) { $currentVersion } else { '(none)' })"
Write-Host "  New     : $Version"
Write-Host ("  Client  : {0:N1} MB" -f ($clientInfo.Length / 1MB))
if ($Channel -eq 'brutal') {
    Write-Host ("  Native  : {0:N1} MB" -f ((Get-Item $NativeLib).Length / 1MB))
}
Write-Host ""

if ($Channel -eq 'brutal') {
    $clientDest = Join-Path $repo 'payloads\brutal\Client.dll'
    $nativeDest = Join-Path $repo 'payloads\brutal\Libraries\libTERMINALX999Cheats.so'
    $nativeDir = Split-Path $nativeDest -Parent
    if (-not (Test-Path $nativeDir)) {
        New-Item -ItemType Directory -Path $nativeDir -Force | Out-Null
    }

    Copy-Item $ClientDll $clientDest -Force
    Copy-Item $NativeLib $nativeDest -Force
    Write-Host ("  [OK] Client.dll ({0:N1} MB)" -f ((Get-Item $clientDest).Length / 1MB))
    Write-Host ("  [OK] libTERMINALX999Cheats.so ({0:N1} MB)" -f ((Get-Item $nativeDest).Length / 1MB))
}
else {
    $clientDest = Join-Path $repo 'payloads\lite\Client.dll'
    $liteDir = Split-Path $clientDest -Parent
    if (-not (Test-Path $liteDir)) {
        New-Item -ItemType Directory -Path $liteDir -Force | Out-Null
    }

    Copy-Item $ClientDll $clientDest -Force
    Write-Host ("  [OK] Client.dll ({0:N1} MB)" -f ((Get-Item $clientDest).Length / 1MB))
}

$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
$manifest.$Channel = $Version.Trim()
$manifest | ConvertTo-Json | Set-Content $manifestPath -Encoding UTF8
Write-Host "  [OK] manifest.json -> $Version"
Write-Host ""

if ($SkipPush) {
    Write-Step "  Skipped git push (-SkipPush)." "Yellow"
    exit 0
}

Push-Location $repo
try {
    git add payloads updates/manifest.json
    $commitMsg = "Publish $Channel $Version"
    git -c user.name="justinkhakhyuu" -c user.email="justinkhakhyuu@users.noreply.github.com" `
        commit -m $commitMsg 2>&1 | ForEach-Object { Write-Host "  $_" }

    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Nothing new to commit, or commit failed." -ForegroundColor Yellow
    }

    git push origin main 2>&1 | ForEach-Object { Write-Host "  $_" }
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Git push failed."
    }

    Write-Host ""
    Write-Step "  Published $Channel $Version to GitHub." "Green"
    Write-Host "  Users can click CHECK FOR UPDATES in the loader."
    Write-Host ""
}
finally {
    Pop-Location
}
