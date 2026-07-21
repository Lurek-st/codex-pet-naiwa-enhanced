param(
  [Parameter(Mandatory = $true)]
  [string]$MsixPath,

  [Parameter(Mandatory = $true)]
  [string]$ExpectedAsarSha256,

  [Parameter(Mandatory = $true)]
  [string]$LogPath,

  [int]$DelaySeconds = 5
)

$ErrorActionPreference = 'Stop'

function Write-InstallLog([string]$Message) {
  $line = '{0:o} {1}' -f (Get-Date), $Message
  Add-Content -LiteralPath $LogPath -Value $line -Encoding utf8
}

try {
  if (-not (Test-Path -LiteralPath $MsixPath -PathType Leaf)) {
    throw "Signed MSIX not found: $MsixPath"
  }

  $signature = Get-AuthenticodeSignature -LiteralPath $MsixPath
  if ($signature.Status -ne 'Valid') {
    throw "MSIX signature is not valid: $($signature.Status)"
  }

  Write-InstallLog "helper started; delaying $DelaySeconds seconds"
  Start-Sleep -Seconds $DelaySeconds

  $package = Get-AppxPackage -Name OpenAI.Codex -ErrorAction Stop | Select-Object -First 1
  $oldInstallRoot = $package.InstallLocation

  Get-Process Codex -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -and $_.Path.StartsWith($oldInstallRoot, [StringComparison]::OrdinalIgnoreCase) } |
    ForEach-Object {
      Write-InstallLog "stopping Codex process pid=$($_.Id)"
      Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }

  Get-CimInstance Win32_Process |
    Where-Object {
      $_.ExecutablePath -and
      $_.ExecutablePath.StartsWith($oldInstallRoot, [StringComparison]::OrdinalIgnoreCase)
    } |
    ForEach-Object {
      Write-InstallLog "stopping package process pid=$($_.ProcessId)"
      Stop-Process -Id ([int]$_.ProcessId) -Force -ErrorAction SilentlyContinue
    }

  Write-InstallLog "removing package $($package.PackageFullName)"
  try {
    Remove-AppxPackage -Package $package.PackageFullName -PreserveApplicationData -ErrorAction Stop
  } catch {
    Write-InstallLog 'PreserveApplicationData was unavailable; retrying normal removal'
    Remove-AppxPackage -Package $package.PackageFullName -ErrorAction Stop
  }

  Write-InstallLog "installing signed MSIX $MsixPath"
  Add-AppxPackage -Path $MsixPath -ErrorAction Stop

  $installed = Get-AppxPackage -Name OpenAI.Codex -ErrorAction Stop | Select-Object -First 1
  $installedAsar = Join-Path $installed.InstallLocation 'app\resources\app.asar'
  $actualAsarSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $installedAsar).Hash
  if ($actualAsarSha256 -ne $ExpectedAsarSha256) {
    throw "Installed app.asar hash mismatch: expected=$ExpectedAsarSha256 actual=$actualAsarSha256"
  }

  Write-InstallLog "install verified package=$($installed.PackageFullName) signature=$($installed.SignatureKind) asar=$actualAsarSha256"
  $application = (Get-AppxPackageManifest -Package $installed).Package.Applications.Application |
    Select-Object -First 1
  $appUserModelId = "$($installed.PackageFamilyName)!$([string]$application.Id)"
  Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe') -ArgumentList "shell:AppsFolder\$appUserModelId" -WindowStyle Hidden
  Write-InstallLog "Codex launched via AppUserModelId: $appUserModelId"
  Write-InstallLog 'RESULT=PASS'
} catch {
  Write-InstallLog "RESULT=FAIL error=$($_.Exception.Message)"
  exit 1
}
