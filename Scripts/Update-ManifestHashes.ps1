param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('brutal', 'lite')]
    [string]$Channel,

    [Parameter(Mandatory = $true)]
    [string]$Version
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$tag = "$Channel-$Version"
$assetDir = Join-Path $repoRoot "release-assets\$tag"
$manifestPath = Join-Path $repoRoot "updates\manifest.json"

if (-not (Test-Path $manifestPath)) {
    Write-Error "Missing manifest: $manifestPath"
}

if (-not (Test-Path $assetDir)) {
    Write-Error "Missing folder: $assetDir"
}

$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
$channelObj = $manifest.channels.$Channel
if (-not $channelObj) {
    Write-Error "Channel '$Channel' not found in manifest."
}

$channelObj.version = $Version
$channelObj.tag = $tag

function Set-FileEntry {
    param(
        [string]$RelativePath,
        [string]$AssetFileName
    )

    $localPath = Join-Path $assetDir $AssetFileName
    if (-not (Test-Path $localPath)) {
        Write-Error "File not found: $localPath"
    }

    $hash = (Get-FileHash -Path $localPath -Algorithm SHA256).Hash
    $size = (Get-Item $localPath).Length
    $url = "https://github.com/justinkhakhyuu/AUTO-UPDATES/releases/download/$tag/$AssetFileName"

    $entry = $channelObj.files.$RelativePath
    if (-not $entry) {
        Write-Error "Manifest has no entry for '$RelativePath'"
    }

    $entry.url = $url
    $entry.sha256 = $hash
    $entry.size = $size

    Write-Host "[OK] $RelativePath"
    Write-Host "     sha256: $hash"
    Write-Host "     size  : $size"
}

if ($Channel -eq 'brutal') {
    Set-FileEntry -RelativePath 'Client.dll' -AssetFileName 'Client.dll'
    Set-FileEntry -RelativePath 'Libraries/libTERMINALX999Cheats.so' -AssetFileName 'libTERMINALX999Cheats.so'
}
else {
    Set-FileEntry -RelativePath 'Client.dll' -AssetFileName 'Client.dll'
}

$manifest | ConvertTo-Json -Depth 8 | Set-Content -Path $manifestPath -Encoding UTF8
Write-Host ""
Write-Host "Updated $manifestPath"
Write-Host "Next: git add updates/manifest.json && git commit && git push"
