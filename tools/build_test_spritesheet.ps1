param(
    [Parameter(Mandatory = $true)]
    [string]$RunningRightGrid,
    [Parameter(Mandatory = $true)]
    [string]$RunningLeftGrid,
    [Parameter(Mandatory = $true)]
    [string]$TypingGrid,
    [string]$Baseline,
    [string]$Output
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($Baseline)) {
    $Baseline = Join-Path $PSScriptRoot '..\naifrog\spritesheet.webp'
}
if ([string]::IsNullOrWhiteSpace($Output)) {
    $Output = Join-Path $PSScriptRoot '..\naifrog-dev\spritesheet.png'
}

$ffmpeg = (Get-Command ffmpeg -ErrorAction Stop).Source
$baselinePath = (Resolve-Path -LiteralPath $Baseline).Path
$rightPath = (Resolve-Path -LiteralPath $RunningRightGrid).Path
$leftPath = (Resolve-Path -LiteralPath $RunningLeftGrid).Path
$typingPath = (Resolve-Path -LiteralPath $TypingGrid).Path
$outputPath = [System.IO.Path]::GetFullPath($Output)
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

if (-not $outputPath.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Output must stay inside the repository: $repoRoot"
}

$buildDir = Join-Path $repoRoot ('work\build-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
$rightRow = Join-Path $buildDir 'running-right-row.png'
$leftRow = Join-Path $buildDir 'running-left-row.png'
$typingRow = Join-Path $buildDir 'typing-row.png'

function Convert-EightFrameGridToRow([string]$InputPath, [string]$RowPath) {
    $filter = '[0:v]split=8[a0][a1][a2][a3][a4][a5][a6][a7];' +
        '[a0]crop=192:208:0:0[f0];[a1]crop=192:208:192:0[f1];' +
        '[a2]crop=192:208:384:0[f2];[a3]crop=192:208:576:0[f3];' +
        '[a4]crop=192:208:0:208[f4];[a5]crop=192:208:192:208[f5];' +
        '[a6]crop=192:208:384:208[f6];[a7]crop=192:208:576:208[f7];' +
        '[f0][f1][f2][f3][f4][f5][f6][f7]hstack=8[out]'
    & $ffmpeg -hide_banner -loglevel error -y -i $InputPath -filter_complex $filter -map '[out]' $RowPath
    if ($LASTEXITCODE -ne 0) { throw "Failed to convert $InputPath" }
}

Convert-EightFrameGridToRow $rightPath $rightRow
Convert-EightFrameGridToRow $leftPath $leftRow
Convert-EightFrameGridToRow $typingPath $typingRow

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputPath) | Out-Null
# Rebuild by stacking whole rows instead of alpha-overlaying them. Overlaying
# changes antialiased edge pixels even when the visible artwork is identical.
$stack = '[0:v]split=8[b0][b3][b4][b5][b7][b8][b9][b10];' +
    '[b0]crop=1536:208:0:0[r0];' +
    '[b3]crop=1536:208:0:624[r3];' +
    '[b4]crop=1536:208:0:832[r4];' +
    '[b5]crop=1536:208:0:1040[r5];' +
    '[b7]crop=1536:208:0:1456[r7];' +
    '[b8]crop=1536:208:0:1664[r8];' +
    '[b9]crop=1536:208:0:1872[r9];' +
    '[b10]crop=1536:208:0:2080[r10];' +
    '[3:v]split=2[r6][r11];' +
    '[r0][1:v][2:v][r3][r4][r5][r6][r7][r8][r9][r10][r11]vstack=12[out]'
& $ffmpeg -hide_banner -loglevel error -y -i $baselinePath -i $rightRow -i $leftRow -i $typingRow `
    -filter_complex $stack -map '[out]' -frames:v 1 $outputPath
if ($LASTEXITCODE -ne 0) { throw 'Failed to assemble the test spritesheet.' }

Write-Output "BUILT=$outputPath"
Write-Output "BUILD_WORK=$buildDir"
