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
    $parsed = $null
    return [System.Version]::TryParse($Value.Trim(), [ref]$parsed)
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

function Show-ProgressLine([string]$Label, [int]$Percent) {
    $pct = [Math]::Max(0, [Math]::Min(100, $Percent))
    $filled = [int]([Math]::Round($pct / 5))
    $bar = ('#' * $filled) + ('-' * (20 - $filled))
    Write-Host ("`r  [{0}] {1,3}%  {2}   " -f $bar, $pct, $Label) -NoNewline
}

function Copy-FileWithProgress([string]$Source, [string]$Destination, [string]$Label) {
    $src = Get-Item -LiteralPath $Source
    $destDir = Split-Path $Destination -Parent
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    $buffer = New-Object byte[] (1024 * 1024)
    $total = [long]$src.Length
    $copied = [long]0
    $lastPct = -1

    $inStream = [System.IO.File]::OpenRead($src.FullName)
    $outStream = [System.IO.File]::Create($Destination)
    try {
        while ($true) {
            $read = $inStream.Read($buffer, 0, $buffer.Length)
            if ($read -le 0) { break }
            $outStream.Write($buffer, 0, $read)
            $copied += $read

            $pct = if ($total -gt 0) { [int](($copied * 100L) / $total) } else { 100 }
            if ($pct -ne $lastPct) {
                $lastPct = $pct
                Show-ProgressLine $Label $pct
            }
        }
    }
    finally {
        $outStream.Dispose()
        $inStream.Dispose()
    }

    Show-ProgressLine $Label 100
    Write-Host ""
}

function Invoke-GitQuiet {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'git'
    $psi.Arguments = ($Arguments | ForEach-Object {
        if ($_ -match '\s') { '"' + $_ + '"' } else { $_ }
    }) -join ' '
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = (Get-Location).Path

    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    return [pscustomobject]@{
        ExitCode = $proc.ExitCode
        StdOut = $stdout
        StdErr = $stderr
    }
}

function Invoke-GitPushWithProgress {
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        Show-ProgressLine 'Uploading to GitHub' 1
        $exitCode = 0

        & git push --progress origin main 2>&1 | ForEach-Object {
            $line = if ($_ -is [System.Management.Automation.ErrorRecord]) {
                $_.ToString()
            } else {
                "$_"
            }

            if ($line -match 'Writing objects:\s+(\d+)%') {
                Show-ProgressLine 'Uploading to GitHub' ([int]$Matches[1])
            }
            elseif ($line -match 'Counting objects:\s+(\d+)%') {
                Show-ProgressLine 'Preparing upload' ([int]$Matches[1])
            }
            elseif ($line -match 'Compressing objects:\s+(\d+)%') {
                Show-ProgressLine 'Compressing' ([int]$Matches[1])
            }
            elseif ($line -match 'Receiving objects:\s+(\d+)%') {
                Show-ProgressLine 'Syncing remote' ([int]$Matches[1])
            }
            elseif ($line -match 'rejected|error:|fatal:') {
                Write-Host ""
                Write-Host "  $line" -ForegroundColor Red
            }
        }

        $exitCode = $LASTEXITCODE
        if ($exitCode -eq 0) {
            Show-ProgressLine 'Uploading to GitHub' 100
            Write-Host ""
        }
        else {
            Write-Host ""
        }

        return $exitCode
    }
    finally {
        $ErrorActionPreference = $oldEap
    }
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

    Copy-FileWithProgress -Source $ClientDll -Destination $clientDest -Label 'Copying Client.dll'
    Copy-FileWithProgress -Source $NativeLib -Destination $nativeDest -Label 'Copying libTERMINALX999Cheats.so'
    Write-Host ("  [OK] Client.dll ({0:N1} MB)" -f ((Get-Item $clientDest).Length / 1MB))
    Write-Host ("  [OK] libTERMINALX999Cheats.so ({0:N1} MB)" -f ((Get-Item $nativeDest).Length / 1MB))
}
else {
    $clientDest = Join-Path $repo 'payloads\lite\Client.dll'
    Copy-FileWithProgress -Source $ClientDll -Destination $clientDest -Label 'Copying Client.dll'
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
    $add = Invoke-GitQuiet -Arguments @('add', 'payloads', 'updates/manifest.json')
    if ($add.ExitCode -ne 0) {
        Write-Host "  git add failed:" -ForegroundColor Red
        Write-Host $add.StdErr
        exit 1
    }

    $commitMsg = "Publish $Channel $Version"
    $commit = Invoke-GitQuiet -Arguments @(
        '-c', 'user.name=justinkhakhyuu',
        '-c', 'user.email=justinkhakhyuu@users.noreply.github.com',
        'commit', '-m', $commitMsg
    )

    if ($commit.ExitCode -eq 0) {
        Write-Host "  [OK] commit: $commitMsg"
    }
    else {
        $combined = ($commit.StdOut + $commit.StdErr)
        if ($combined -match 'nothing to commit') {
            Write-Host "  [OK] nothing new to commit (files already current)"
        }
        else {
            Write-Host "  Commit warning:" -ForegroundColor Yellow
            if ($commit.StdOut) { Write-Host $commit.StdOut }
            if ($commit.StdErr) { Write-Host $commit.StdErr }
        }
    }

    Write-Host ""
    $pushCode = Invoke-GitPushWithProgress
    if ($pushCode -ne 0) {
        Write-Host "  Git push failed (exit $pushCode)." -ForegroundColor Red
        exit 1
    }

    Write-Host ""
    Write-Step "  Published $Channel $Version to GitHub." "Green"
    Write-Host "  Users can click CHECK FOR UPDATES in the loader."
    Write-Host ""
}
finally {
    Pop-Location
}
