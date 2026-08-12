param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('brutal', 'lite')]
    [string]$Channel,

    [Parameter(Mandatory = $true)]
    [string]$Version,

    [string]$BrutalClient,
    [string]$BrutalNative,
    [string]$LiteClient
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$manifest = Join-Path $repo 'updates\manifest.json'

switch ($Channel) {
    'brutal' {
        if (-not $BrutalClient) { $BrutalClient = Read-Host "Path to brutal Client.dll" }
        if (-not $BrutalNative) { $BrutalNative = Read-Host "Path to libTERMINALX999Cheats.so" }
        Copy-Item $BrutalClient (Join-Path $repo 'payloads\brutal\Client.dll') -Force
        Copy-Item $BrutalNative (Join-Path $repo 'payloads\brutal\Libraries\libTERMINALX999Cheats.so') -Force
    }
    'lite' {
        if (-not $LiteClient) { $LiteClient = Read-Host "Path to lite Client.dll" }
        Copy-Item $LiteClient (Join-Path $repo 'payloads\lite\Client.dll') -Force
    }
}

$data = Get-Content $manifest -Raw | ConvertFrom-Json
$data.$Channel = $Version
$data | ConvertTo-Json | Set-Content $manifest -Encoding UTF8
Write-Host "Done. $Channel = $Version. Now: git add -A; git commit; git push"
