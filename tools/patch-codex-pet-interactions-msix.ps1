param(
  [switch]$DryRun,
  [switch]$Install,
  [switch]$BuildOnly,
  [switch]$Launch,
  [switch]$KeepWorkDir,
  [switch]$InstallPrerequisites,
  [string]$OutputRoot = (Join-Path $PSScriptRoot '..\work\pet-host-msix')
)

$ErrorActionPreference = 'Stop'
$LogPrefix = '[codex-pet-interactions-msix]'
$WindowsSdkBuildToolsPackageId = 'microsoft.windows.sdk.buildtools'
$WindowsSdkBuildToolsVersion = '10.0.26100.7705'
$InstalledWindowsSdkViaNuGet = $false

if ((@($DryRun, $Install, $BuildOnly) | Where-Object { $_ }).Count -gt 1) {
  throw "$LogPrefix error: choose exactly one of -DryRun, -BuildOnly, or -Install"
}
if (-not $Install -and -not $BuildOnly) {
  $DryRun = $true
}
if ($Launch -and -not $Install) {
  throw "$LogPrefix error: -Launch is valid only with -Install"
}

function Write-Log([string]$Message) {
  Write-Host "$LogPrefix $Message"
}

function Fail([string]$Message) {
  throw "$LogPrefix error: $Message"
}

function Get-RequiredCommand([string]$Name) {
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $cmd) {
    Fail "required command not found: $Name"
  }
  return $cmd.Source
}

function Remove-DirectoryRobust {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$RequiredRoot
  )
  if (-not (Test-Path -LiteralPath $Path)) {
    return
  }
  if (-not (Test-Path -LiteralPath $RequiredRoot)) {
    Fail "safe deletion root does not exist: $RequiredRoot"
  }
  $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
  $root = (Resolve-Path -LiteralPath $RequiredRoot -ErrorAction Stop).ProviderPath.TrimEnd('\')
  $comparison = [StringComparison]::OrdinalIgnoreCase
  if ($resolved.Equals($root, $comparison) -or -not $resolved.StartsWith($root + '\', $comparison)) {
    Fail "refusing to recursively delete outside safe root: $resolved"
  }
  try {
    Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Stop
  } catch {
    $longPath = '\\?\' + $resolved
    [System.IO.Directory]::Delete($longPath, $true)
  }
}

function Find-WindowsSdkTool([string]$ToolName) {
  $cmd = Get-Command $ToolName -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd) {
    return $cmd.Source
  }
  $roots = @(
    (Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'),
    (Join-Path $env:ProgramFiles 'Windows Kits\10\bin'),
    (Join-Path $OutputRoot 'sdk-buildtools')
  ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
  foreach ($root in $roots) {
    $hit = Get-ChildItem -LiteralPath $root -Recurse -Filter $ToolName -File -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -match '\\x64\\' } |
      Sort-Object FullName -Descending |
      Select-Object -First 1
    if ($hit) {
      return $hit.FullName
    }
  }
  return $null
}

function Install-WindowsSdkBuildToolsViaNuGet {
  if ((Find-WindowsSdkTool 'makeappx.exe') -and (Find-WindowsSdkTool 'signtool.exe')) {
    return
  }
  $cacheRoot = Join-Path $OutputRoot 'sdk-buildtools'
  $packageRoot = Join-Path $cacheRoot $WindowsSdkBuildToolsVersion
  $x64Root = Join-Path $packageRoot 'bin'
  if (Test-Path -LiteralPath $packageRoot) {
    Remove-DirectoryRobust -Path $packageRoot -RequiredRoot $cacheRoot
  }
  New-Item -ItemType Directory -Force -Path $packageRoot | Out-Null
  $packageId = $WindowsSdkBuildToolsPackageId.ToLowerInvariant()
  $nupkg = Join-Path $cacheRoot "$packageId.$WindowsSdkBuildToolsVersion.nupkg"
  $zip = Join-Path $cacheRoot "$packageId.$WindowsSdkBuildToolsVersion.zip"
  $url = "https://api.nuget.org/v3-flatcontainer/$packageId/$WindowsSdkBuildToolsVersion/$packageId.$WindowsSdkBuildToolsVersion.nupkg"
  Write-Log "downloading Windows SDK BuildTools to $cacheRoot"
  $curl = Get-RequiredCommand 'curl.exe'
  # The desktop environment can retain stale localhost proxy variables while
  # Windows TUN networking works directly, so bypass only those variables for
  # this public NuGet download.
  & $curl --noproxy '*' --fail --location --silent --show-error --output $nupkg $url
  if ($LASTEXITCODE -ne 0) {
    Fail "Windows SDK BuildTools download failed with exit code $LASTEXITCODE"
  }
  Copy-Item -LiteralPath $nupkg -Destination $zip -Force
  Expand-Archive -LiteralPath $zip -DestinationPath $packageRoot -Force
  Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
  $makeappx = Get-ChildItem -LiteralPath $x64Root -Recurse -Filter 'makeappx.exe' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\x64\\' } |
    Select-Object -First 1
  $signtool = Get-ChildItem -LiteralPath $x64Root -Recurse -Filter 'signtool.exe' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\x64\\' } |
    Select-Object -First 1
  if (-not $makeappx -or -not $signtool) {
    Fail "NuGet Windows SDK BuildTools did not provide required x64 MSIX tools: $packageRoot"
  }
  $script:InstalledWindowsSdkViaNuGet = $true
}

function Require-WindowsSdkTool([string]$ToolName) {
  $tool = Find-WindowsSdkTool $ToolName
  if (-not $tool -and $InstallPrerequisites) {
    Install-WindowsSdkBuildToolsViaNuGet
    $tool = Find-WindowsSdkTool $ToolName
  }
  if (-not $tool) {
    Fail "$ToolName not found. Re-run with -InstallPrerequisites."
  }
  return $tool
}

function Convert-BytesToHex([byte[]]$Bytes) {
  return (($Bytes | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Get-AsarHeaderSha256([string]$AsarPath) {
  $fs = [System.IO.File]::Open($AsarPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
  try {
    $pickleHeader = New-Object byte[] 16
    if ($fs.Read($pickleHeader, 0, 16) -ne 16) {
      Fail 'could not read asar pickle header'
    }
    $headerSize = [BitConverter]::ToUInt32($pickleHeader, 12)
    if ($headerSize -le 0 -or $headerSize -gt ($fs.Length - 16)) {
      Fail "invalid asar JSON header size: $headerSize"
    }
    $headerBytes = New-Object byte[] $headerSize
    if ($fs.Read($headerBytes, 0, [int]$headerSize) -ne [int]$headerSize) {
      Fail 'could not read asar header bytes'
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
      return (Convert-BytesToHex $sha.ComputeHash($headerBytes))
    } finally {
      $sha.Dispose()
    }
  } finally {
    $fs.Dispose()
  }
}

function Update-CodexExeAsarIntegrity {
  param(
    [Parameter(Mandatory = $true)][string]$ExePath,
    [Parameter(Mandatory = $true)][string]$AsarHash
  )
  $bytes = [System.IO.File]::ReadAllBytes($ExePath)
  $text = [System.Text.Encoding]::ASCII.GetString($bytes)
  $pattern = '\[\{"file":"resources\\\\app\.asar","alg":"SHA256","value":"([0-9a-fA-F]{64})"\}\]'
  $match = [regex]::Match($text, $pattern)
  if (-not $match.Success) {
    if ($text.Contains('app.asar')) {
      Fail 'could not find Electron ASAR integrity JSON inside Codex.exe'
    }
    Write-Log 'Codex.exe ASAR integrity JSON not present; skipping executable integrity update'
    return
  }
  $oldHash = $match.Groups[1].Value
  if ($oldHash -eq $AsarHash) {
    Write-Log "Codex.exe ASAR integrity already current: $AsarHash"
    return
  }
  $oldBytes = [System.Text.Encoding]::ASCII.GetBytes($oldHash)
  $newBytes = [System.Text.Encoding]::ASCII.GetBytes($AsarHash)
  $pos = -1
  for ($i = 0; $i -le $bytes.Length - $oldBytes.Length; $i++) {
    $ok = $true
    for ($j = 0; $j -lt $oldBytes.Length; $j++) {
      if ($bytes[$i + $j] -ne $oldBytes[$j]) {
        $ok = $false
        break
      }
    }
    if ($ok) {
      $pos = $i
      break
    }
  }
  if ($pos -lt 0) {
    Fail 'could not locate ASAR integrity hash bytes in Codex.exe'
  }
  [Array]::Copy($newBytes, 0, $bytes, $pos, $newBytes.Length)
  [System.IO.File]::WriteAllBytes($ExePath, $bytes)
  Write-Log "updated Codex.exe ASAR integrity: $oldHash -> $AsarHash"
}

function Get-OrCreateSigningCertificate([string]$Publisher) {
  $cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue |
    Where-Object { $_.Subject -eq $Publisher } |
    Sort-Object NotAfter -Descending |
    Select-Object -First 1
  if ($cert) {
    Write-Log "using existing signing certificate: $($cert.Thumbprint)"
    return $cert
  }
  Write-Log "creating signing certificate: $Publisher"
  return New-SelfSignedCertificate -Type CodeSigningCert -Subject $Publisher -CertStoreLocation Cert:\CurrentUser\My -NotAfter (Get-Date).AddYears(5)
}

function Trust-SigningCertificate($Cert) {
  $tempCert = Join-Path $OutputRoot ('codex-msix-signing-' + $Cert.Thumbprint + '.cer')
  Export-Certificate -Cert $Cert -FilePath $tempCert -Force | Out-Null
  Import-Certificate -FilePath $tempCert -CertStoreLocation Cert:\CurrentUser\TrustedPeople | Out-Null
  Remove-Item -LiteralPath $tempCert -Force -ErrorAction SilentlyContinue
}

function Stop-CodexDesktopProcesses([string]$InstallLocation) {
  $targetRoot = $InstallLocation.TrimEnd('\')
  $processes = Get-Process -Name 'ChatGPT','Codex' -ErrorAction SilentlyContinue | Where-Object {
    $_.Path -and $_.Path.StartsWith($targetRoot, [StringComparison]::OrdinalIgnoreCase)
  }
  foreach ($process in $processes) {
    Write-Log "stopping Codex desktop process pid=$($process.Id)"
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
  }
  $appServers = Get-CimInstance Win32_Process |
    Where-Object { $_.Name -eq 'codex.exe' -and $_.CommandLine -like '*WindowsApps\\OpenAI.Codex_*app-server*' }
  foreach ($server in $appServers) {
    Write-Log "stopping Codex app-server pid=$($server.ProcessId)"
    Stop-Process -Id ([int]$server.ProcessId) -Force -ErrorAction SilentlyContinue
  }
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$OutputRoot = (Resolve-Path -LiteralPath $OutputRoot).ProviderPath
$pkg = Get-AppxPackage -Name OpenAI.Codex -ErrorAction Stop | Select-Object -First 1
if (-not $pkg -or -not $pkg.InstallLocation) {
  Fail 'OpenAI.Codex package not found'
}

$sourcePackageRoot = $pkg.InstallLocation
$sourceAsar = Join-Path $sourcePackageRoot 'app\resources\app.asar'
if (-not (Test-Path -LiteralPath $sourceAsar -PathType Leaf)) {
  Fail "app.asar not found: $sourceAsar"
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$workRoot = Join-Path $OutputRoot "pet-interactions-$($pkg.Version)-$stamp"
$workPackageRoot = Join-Path $workRoot 'package'
$asarDir = Join-Path $workRoot 'app-asar'
$msixPath = Join-Path $OutputRoot "OpenAI.Codex_$($pkg.Version)_pet-interactions-patched.msix"
$patcher = Join-Path $PSScriptRoot 'patch-codex-pet-interactions.cjs'
$laughAudioSource = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\assets\audio\nailong-laugh.mp3'))
$installedSuccessfully = $false

if (-not (Test-Path -LiteralPath $patcher -PathType Leaf)) {
  Fail "pet interactions patcher not found: $patcher"
}
if (-not (Test-Path -LiteralPath $laughAudioSource -PathType Leaf)) {
  Fail "laugh audio asset not found: $laughAudioSource"
}

try {
  Write-Log "source package: $sourcePackageRoot"
  Write-Log "work root: $workRoot"
  New-Item -ItemType Directory -Force -Path $workPackageRoot | Out-Null
  Write-Log 'copying package layout'
  # Store package files are EFS-marked on this machine.  Copy data and
  # timestamps without carrying the Encrypted attribute onto the D: build.
  $robocopy = Join-Path $env:SystemRoot 'System32\robocopy.exe'
  $robocopyArgs = @(
    ('"' + $sourcePackageRoot + '"'),
    ('"' + $workPackageRoot + '"'),
    '/MIR','/COPY:DT','/DCOPY:T','/R:2','/W:1','/NFL','/NDL','/NJH','/NJS','/NP'
  )
  $copyProcess = Start-Process -FilePath $robocopy -ArgumentList $robocopyArgs -Wait -PassThru -WindowStyle Hidden
  if ($copyProcess.ExitCode -gt 7) {
    Fail "robocopy failed with exit code $($copyProcess.ExitCode)"
  }
  $copiedAsar = Join-Path $workPackageRoot 'app\resources\app.asar'
  if (-not (Test-Path -LiteralPath $copiedAsar -PathType Leaf)) {
    Fail "package copy did not produce app.asar: $copiedAsar"
  }
  if ((Get-Item -LiteralPath $copiedAsar).Length -ne (Get-Item -LiteralPath $sourceAsar).Length) {
    Fail 'copied app.asar size does not match the source'
  }
  foreach ($rel in @('AppxSignature.p7x', 'AppxBlockMap.xml', 'AppxMetadata\CodeIntegrity.cat')) {
    $artifact = Join-Path $workPackageRoot $rel
    if (Test-Path -LiteralPath $artifact) {
      Remove-Item -LiteralPath $artifact -Force
    }
  }

  $npm = Get-RequiredCommand 'npm.cmd'
  $workAsar = Join-Path $workPackageRoot 'app\resources\app.asar'
  Write-Log 'extracting app.asar'
  & $npm exec --offline --yes --package=asar -- asar extract $workAsar $asarDir
  if ($LASTEXITCODE -ne 0) {
    Fail "offline asar extract failed with exit code $LASTEXITCODE"
  }

  $laughAudioTarget = Join-Path $asarDir 'webview\assets\nailong-laugh.mp3'
  Copy-Item -LiteralPath $laughAudioSource -Destination $laughAudioTarget -Force
  $laughSourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $laughAudioSource).Hash
  $laughTargetHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $laughAudioTarget).Hash
  if ($laughSourceHash -ne $laughTargetHash) {
    Fail 'copied laugh audio hash does not match the source asset'
  }
  Write-Log "laugh audio asset sha256: $laughTargetHash"

  Write-Log 'patching custom pet drag, hover audio, v3 loader, waiting typing, and tool-execution typing interactions'
  $patchResult = & node $patcher $asarDir
  if ($LASTEXITCODE -ne 0) {
    Fail "pet interactions patch failed with exit code $LASTEXITCODE"
  }
  Write-Log "pet interactions patch result: $($patchResult -join '; ')"
  $petLoaderSyntaxTarget = Get-ChildItem -LiteralPath (Join-Path $asarDir '.vite\build') -Filter 'src-*.js' -File |
    Where-Object {
      $source = [IO.File]::ReadAllText($_.FullName)
      $source.Contains('CODEX_PET_V3_HEIGHT=2496')
    } |
    Select-Object -First 1
  $syntaxTargets = @(
    (Get-ChildItem -LiteralPath (Join-Path $asarDir 'webview\assets') -Filter 'avatar-overlay-native-page-*.js' -File | Select-Object -First 1),
    (Get-ChildItem -LiteralPath (Join-Path $asarDir 'webview\assets') -Filter 'avatar-overlay-native-frame-*.js' -File | Select-Object -First 1),
    (Get-ChildItem -LiteralPath (Join-Path $asarDir 'webview\assets') -Filter 'avatar-overlay-pill-material.module-*.js' -File | Select-Object -First 1),
    (Get-ChildItem -LiteralPath (Join-Path $asarDir 'webview\assets') -Filter 'use-avatar-overlay-selection-*.js' -File | Select-Object -First 1),
    (Get-ChildItem -LiteralPath (Join-Path $asarDir 'webview\assets') -Filter 'codex-avatar-*.js' -File | Select-Object -First 1),
    (Get-ChildItem -LiteralPath (Join-Path $asarDir 'webview\assets') -Filter 'avatar-spritesheet-*.js' -File | Select-Object -First 1),
    (Get-ChildItem -LiteralPath (Join-Path $asarDir '.vite\build') -Filter 'main-*.js' -File | Select-Object -First 1),
    $petLoaderSyntaxTarget
  )
  if ($syntaxTargets.Count -ne 8 -or $syntaxTargets.Where({ $_ -eq $null }).Count -ne 0) {
    Fail 'one or more patched JavaScript assets are missing'
  }
  foreach ($syntaxTarget in $syntaxTargets) {
    & node --check $syntaxTarget.FullName
    if ($LASTEXITCODE -ne 0) {
      Fail "node syntax check failed for $($syntaxTarget.FullName)"
    }
  }

  if ($DryRun) {
    Write-Log 'dry run passed; package was not repacked or installed'
    return
  }

  Write-Log 'packing app.asar'
  & $npm exec --offline --yes --package=asar -- asar pack $asarDir $workAsar
  if ($LASTEXITCODE -ne 0) {
    Fail "offline asar pack failed with exit code $LASTEXITCODE"
  }

  $asarHash = Get-AsarHeaderSha256 $workAsar
  Write-Log "app.asar header sha256: $asarHash"
  Update-CodexExeAsarIntegrity -ExePath (Join-Path $workPackageRoot 'app\Codex.exe') -AsarHash $asarHash

  $makeappx = Require-WindowsSdkTool 'makeappx.exe'
  $signtool = Require-WindowsSdkTool 'signtool.exe'
  [xml]$manifest = Get-Content -Raw -LiteralPath (Join-Path $workPackageRoot 'AppxManifest.xml')
  $publisher = [string]$manifest.Package.Identity.Publisher
  $cert = Get-OrCreateSigningCertificate $publisher
  Trust-SigningCertificate $cert
  if (Test-Path -LiteralPath $msixPath) {
    Remove-Item -LiteralPath $msixPath -Force
  }
  Write-Log "packing MSIX: $msixPath"
  & $makeappx pack /d $workPackageRoot /p $msixPath /o
  if ($LASTEXITCODE -ne 0) {
    Fail "makeappx pack failed with exit code $LASTEXITCODE"
  }
  Write-Log 'signing MSIX'
  & $signtool sign /fd SHA256 /sha1 $cert.Thumbprint $msixPath
  if ($LASTEXITCODE -ne 0) {
    Fail "signtool sign failed with exit code $LASTEXITCODE"
  }

  if ($BuildOnly) {
    Write-Log "build-only passed; signed MSIX was not installed: $msixPath"
  }

  if ($Install) {
    Stop-CodexDesktopProcesses $sourcePackageRoot
    Write-Log "removing existing package: $($pkg.PackageFullName)"
    try {
      Remove-AppxPackage -Package $pkg.PackageFullName -PreserveApplicationData -ErrorAction Stop
    } catch {
      Write-Log 'PreserveApplicationData unsupported; retrying normal Remove-AppxPackage'
      Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
    }
    Write-Log "installing patched MSIX: $msixPath"
    Add-AppxPackage -Path $msixPath -ErrorAction Stop
    $installed = Get-AppxPackage -Name OpenAI.Codex -ErrorAction Stop | Select-Object -First 1
    Write-Log "installed package: $($installed.PackageFullName)"
    $installedSuccessfully = $true
    if ($Launch) {
      $application = (Get-AppxPackageManifest -Package $installed).Package.Applications.Application |
        Select-Object -First 1
      $relativeExe = ([string]$application.Executable).Replace('/', '\')
      $exe = Join-Path $installed.InstallLocation $relativeExe
      Write-Log "launching Codex: $exe"
      Start-Process -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe) -WindowStyle Hidden
    }
  }

  Write-Log 'done'
} finally {
  if ($KeepWorkDir) {
    Write-Log "keeping work root: $workRoot"
  } else {
    Remove-DirectoryRobust -Path $workRoot -RequiredRoot $OutputRoot
    if ($installedSuccessfully -and (Test-Path -LiteralPath $msixPath -PathType Leaf)) {
      Remove-Item -LiteralPath $msixPath -Force -ErrorAction SilentlyContinue
      Write-Log "removed installed patched MSIX artifact: $msixPath"
    }
    if ($InstalledWindowsSdkViaNuGet) {
      $sdkRoot = Join-Path $OutputRoot 'sdk-buildtools'
      if (Test-Path -LiteralPath $sdkRoot) {
        Remove-DirectoryRobust -Path $sdkRoot -RequiredRoot $OutputRoot
      }
    }
  }
}
