param(
    [string]$Source,
    [string]$CodexRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($Source)) {
    $Source = Join-Path $PSScriptRoot '..\naifrog-dev'
}
if ([string]::IsNullOrWhiteSpace($CodexRoot)) {
    $CodexRoot = Join-Path $env:USERPROFILE '.codex'
}

$sourcePath = (Resolve-Path -LiteralPath $Source).Path
$targetRoot = [System.IO.Path]::GetFullPath((Join-Path $CodexRoot 'pets'))
$targetPath = [System.IO.Path]::GetFullPath((Join-Path $targetRoot 'naifrog-dev'))

if (-not $targetPath.StartsWith($targetRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Unsafe target path: $targetPath"
}

python (Join-Path $PSScriptRoot 'validate_pet.py') $sourcePath
if ($LASTEXITCODE -ne 0) { throw 'Pet validation failed; installation stopped.' }

New-Item -ItemType Directory -Force -Path $targetPath | Out-Null
Copy-Item -LiteralPath (Join-Path $sourcePath 'pet.json') -Destination $targetPath -Force
$metadata = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $sourcePath 'pet.json') | ConvertFrom-Json
Copy-Item -LiteralPath (Join-Path $sourcePath $metadata.spritesheetPath) -Destination $targetPath -Force

Write-Output "INSTALLED=$targetPath"
Write-Output 'NEXT=Codex Settings -> Pets -> Custom pets -> Refresh -> 奶蛙开发版'
