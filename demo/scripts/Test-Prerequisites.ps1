#Requires -Version 5.1
<#
.SYNOPSIS
    Validates the current platform, Connext installation, build artifacts,
    native toolchain, Docker, ports, and GUI availability for the demo.
#>
[CmdletBinding()]
param(
    [string]$ConnextDir,
    [string]$ConnextArch,
    [string]$GatewayInstallDir,
    [string]$BootstrapServers = "localhost:9092"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "Demo.Common.ps1")

$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Write-Check {
    param(
        [string]$Name,
        [bool]$Ok,
        [string]$Detail = "",
        [switch]$WarnOnly
    )

    if ($Ok) {
        Write-Host "[ OK ] $Name" -ForegroundColor Green
    } elseif ($WarnOnly) {
        Write-Host "[WARN] $Name - $Detail" -ForegroundColor Yellow
        $warnings.Add("$Name - $Detail")
    } else {
        Write-Host "[FAIL] $Name - $Detail" -ForegroundColor Red
        $failures.Add("$Name - $Detail")
    }
}

function Invoke-PrerequisiteProbe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [string[]]$ArgumentList = @()
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $nativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference `
        -ErrorAction SilentlyContinue
    if ($nativePreference) {
        $previousNativePreference = $nativePreference.Value
        Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $false
    }

    try {
        $ErrorActionPreference = "Continue"
        $output = (& $FilePath @ArgumentList 2>&1 | Out-String)
        $exitCode = $LASTEXITCODE
    } catch {
        $output = $_ | Out-String
        $exitCode = -1
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
        if ($nativePreference) {
            Set-Variable -Name PSNativeCommandUseErrorActionPreference `
                -Value $previousNativePreference
        }
    }

    [pscustomobject]@{
        ExitCode = $exitCode
        Output = $output.Trim()
    }
}

$platform = Get-DemoPlatformInfo
Write-Host "=== Platform ===" -ForegroundColor Cyan
$supportedPlatform = $true
$platformFailure = ""
try {
    Assert-DemoSupportedPlatform -PlatformInfo $platform
} catch {
    $supportedPlatform = $false
    $platformFailure = $_.Exception.Message
}
Write-Check "$($platform.Platform) $($platform.OSArchitecture) host" `
    $supportedPlatform $platformFailure
Write-Check "Native PowerShell process ($($platform.ProcessArchitecture))" `
    ($platform.ProcessArchitecture -match $platform.OSArchitecture) `
    "Install a native PowerShell build; do not run the macOS workflow under Rosetta"
if ($platform.IsWindows) {
    Write-Check "PowerShell 5.1 or newer ($($PSVersionTable.PSVersion))" `
        ($PSVersionTable.PSVersion.Major -ge 5)
} else {
    Write-Check "PowerShell 7 or newer ($($PSVersionTable.PSVersion))" `
        ($PSVersionTable.PSVersion.Major -ge 7) `
        "Install PowerShell 7 for Unix demo scripts"
}

$paths = Get-DemoPaths -ScriptRoot $PSScriptRoot
if (-not $GatewayInstallDir) {
    $GatewayInstallDir = $paths.GatewayInstall
}

Write-Host "`n=== Connext DDS installation ===" -ForegroundColor Cyan
$resolvedConnext = $false
try {
    $ConnextDir = Resolve-DemoConnextDirectory `
        -ConnextDir $ConnextDir `
        -PlatformInfo $platform
    $resolvedConnext = $true
    Write-Check "Connext directory exists ($ConnextDir)" $true
} catch {
    Write-Check "Connext directory exists" $false $_.Exception.Message
}

$resolvedArchitecture = $false
if ($resolvedConnext) {
    try {
        $ConnextArch = Resolve-DemoConnextArchitecture `
            -ConnextDir $ConnextDir `
            -ConnextArch $ConnextArch `
            -PlatformInfo $platform
        $resolvedArchitecture = $true
        Write-Check "Connext architecture discovered ($ConnextArch)" $true
    } catch {
        Write-Check "Connext architecture discovered" $false $_.Exception.Message
    }
}

if ($resolvedConnext) {
    $names = Get-DemoPlatformArtifacts -PlatformInfo $platform
    $routingServiceLauncher = Join-Path (Join-Path $ConnextDir "bin") $names.RoutingServiceLauncher
    $shapesDemoLauncher = Join-Path (Join-Path $ConnextDir "bin") $names.ShapesDemoLauncher
    Write-Check "RTI Routing Service launcher present" `
        (Test-Path -LiteralPath $routingServiceLauncher -PathType Leaf) `
        "Expected $routingServiceLauncher"
    Write-Check "RTI Shapes Demo launcher present" `
        (Test-Path -LiteralPath $shapesDemoLauncher -PathType Leaf) `
        "Expected $shapesDemoLauncher"
}

if ($resolvedArchitecture -and $platform.IsMacOS) {
    $connextLibDir = Join-Path (Join-Path $ConnextDir "lib") $ConnextArch
    $sampleLibrary = Get-ChildItem -LiteralPath $connextLibDir -Filter "*.dylib" -File |
        Select-Object -First 1
    if ($sampleLibrary) {
        $fileProbe = Invoke-PrerequisiteProbe -FilePath "file" `
            -ArgumentList @($sampleLibrary.FullName)
        Write-Check "Connext target libraries are native ARM64" `
            ($fileProbe.ExitCode -eq 0 -and $fileProbe.Output -match "arm64" -and
                $fileProbe.Output -notmatch "x86_64") `
            $fileProbe.Output
    } else {
        Write-Check "Connext target libraries are native ARM64" $false `
            "No dylibs found under $connextLibDir"
    }
}

Write-Host "`n=== License ===" -ForegroundColor Cyan
$licenseCandidates = New-Object System.Collections.Generic.List[string]
if ($env:RTI_LICENSE_FILE) {
    $licenseCandidates.Add($env:RTI_LICENSE_FILE)
}
if ($resolvedConnext) {
    $licenseCandidates.Add((Join-Path $ConnextDir "rti_license.dat"))
}
$userDirectory = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
if ($userDirectory) {
    $licenseCandidates.Add((Join-Path $userDirectory "rti_license.dat"))
}
$licenseFound = $licenseCandidates | Where-Object {
    Test-Path -LiteralPath $_ -PathType Leaf
} | Select-Object -First 1
if ($licenseFound) {
    Write-Check "License file found ($licenseFound)" $true
} else {
    Write-Check "License file found" $false `
        "Set RTI_LICENSE_FILE or install rti_license.dat; a configured license server may also be valid" `
        -WarnOnly
}

Write-Host "`n=== Native build tools ===" -ForegroundColor Cyan
$cmakeCommand = Get-Command cmake -ErrorAction SilentlyContinue
Write-Check "CMake available" ($null -ne $cmakeCommand) `
    "Install CMake and open a new terminal"
if (-not $platform.IsWindows) {
    $ninjaCommand = Get-Command ninja -ErrorAction SilentlyContinue
    Write-Check "Ninja available" ($null -ne $ninjaCommand) `
        "Install Ninja for the Unix Gateway build"
}
if ($platform.IsMacOS) {
    Write-Check "Apple Clang available" `
        ($null -ne (Get-Command clang -ErrorAction SilentlyContinue)) `
        "Install the Xcode command-line developer tools"
} elseif ($platform.IsLinux) {
    Write-Check "GCC available" `
        ($null -ne (Get-Command gcc -ErrorAction SilentlyContinue)) `
        "Install Ubuntu's build-essential package"
}

Write-Host "`n=== Gateway build artifacts ===" -ForegroundColor Cyan
$requiredArtifacts = Get-DemoRequiredArtifacts `
    -GatewayInstallDir $GatewayInstallDir `
    -PlatformInfo $platform
foreach ($artifact in $requiredArtifacts) {
    Write-Check "Build artifact present ($(Split-Path $artifact -Leaf))" `
        (Test-Path -LiteralPath $artifact -PathType Leaf) `
        "Missing $artifact - run Build-Gateway.ps1"
}

if ($platform.IsMacOS) {
    $installedLibraries = @()
    $gatewayLibDir = Join-Path $GatewayInstallDir "lib"
    if (Test-Path -LiteralPath $gatewayLibDir -PathType Container) {
        $installedLibraries = @(Get-ChildItem -LiteralPath $gatewayLibDir `
            -Filter "*.dylib" -File | Select-Object -ExpandProperty FullName)
    }
    $nativeArtifacts = @($installedLibraries)
    $nativeArtifacts += @($requiredArtifacts | Where-Object {
        $_ -notlike "*.pbdesc" -and (Test-Path -LiteralPath $_ -PathType Leaf)
    })
    $nativeArtifacts = @($nativeArtifacts | Sort-Object -Unique)

    foreach ($artifact in $nativeArtifacts) {
        $fileProbe = Invoke-PrerequisiteProbe -FilePath "file" -ArgumentList @($artifact)
        Write-Check "Native ARM64 artifact ($(Split-Path $artifact -Leaf))" `
            ($fileProbe.ExitCode -eq 0 -and $fileProbe.Output -match "arm64" -and
                $fileProbe.Output -notmatch "x86_64") `
            $fileProbe.Output

        $otoolProbe = Invoke-PrerequisiteProbe -FilePath "otool" `
            -ArgumentList @("-L", $artifact)
        Write-Check "No build-host package dependency ($(Split-Path $artifact -Leaf))" `
            ($otoolProbe.ExitCode -eq 0 -and
                $otoolProbe.Output -notmatch "/opt/homebrew|/usr/local|/opt/local") `
            $otoolProbe.Output
    }
}

if ($resolvedArchitecture) {
    $runtimeEnvironment = Get-DemoRuntimeEnvironment `
        -GatewayInstallDir $GatewayInstallDir `
        -ConnextDir $ConnextDir `
        -ConnextArch $ConnextArch `
        -PlatformInfo $platform
    Write-Check "Gateway runtime library directory present" `
        (Test-Path -LiteralPath $runtimeEnvironment.GatewayLibDir -PathType Container) `
        "Expected $($runtimeEnvironment.GatewayLibDir)"
    Write-Check "Connext runtime library directory present" `
        (Test-Path -LiteralPath $runtimeEnvironment.ConnextLibDir -PathType Container) `
        "Expected $($runtimeEnvironment.ConnextLibDir)"
    Write-Host "      Child processes will receive $($runtimeEnvironment.VariableName)." -ForegroundColor DarkGray
}

Write-Host "`n=== Docker ===" -ForegroundColor Cyan
$dockerCommand = Get-Command docker -ErrorAction SilentlyContinue
Write-Check "Docker CLI available" ($null -ne $dockerCommand) `
    "Install Docker Desktop / Docker Engine"
$dockerInfoOk = $false
$dockerComposeOk = $false
$dockerPorts = ""
if ($dockerCommand) {
    $dockerInfoProbe = Invoke-PrerequisiteProbe -FilePath "docker" -ArgumentList @("info")
    $dockerInfoOk = ($dockerInfoProbe.ExitCode -eq 0)
    $dockerComposeProbe = Invoke-PrerequisiteProbe -FilePath "docker" `
        -ArgumentList @("compose", "version")
    $dockerComposeOk = ($dockerComposeProbe.ExitCode -eq 0)
    if ($dockerInfoOk) {
        $dockerPsProbe = Invoke-PrerequisiteProbe -FilePath "docker" `
            -ArgumentList @("ps", "--format", "{{.Ports}} {{.Names}}")
        if ($dockerPsProbe.ExitCode -eq 0) {
            $dockerPorts = $dockerPsProbe.Output
        }
    }
    Write-Check "Docker daemon reachable" $dockerInfoOk `
        "Start Docker Desktop (or the Docker service) before running Start-Kafka.ps1"
    Write-Check "Docker Compose plugin available" $dockerComposeOk `
        "Docker Compose v2 (docker compose) is required"
}

Write-Host "`n=== Ports ===" -ForegroundColor Cyan
foreach ($port in @(9092, 9021)) {
    $available = Test-DemoLocalPortAvailable -Port $port
    $ownedByDocker = (-not $available -and $dockerPorts -match ":${port}->")
    if ($available) {
        Write-Check "Port $port available" $true
    } elseif ($ownedByDocker) {
        Write-Check "Port $port already published by Docker" $true
    } else {
        Write-Check "Port $port available" $false `
            "The port is already in use by a non-Docker or unidentified process" `
            -WarnOnly
    }
}

Write-Host "`n=== Broker connectivity (only if already running) ===" -ForegroundColor Cyan
$bootstrapUri = $null
try {
    $firstBootstrapServer = ($BootstrapServers -split ",")[0].Trim()
    $bootstrapUri = [System.Uri]("tcp://$firstBootstrapServer")
} catch {
    Write-Check "Kafka bootstrap address is valid" $false `
        "Expected host:port, received '$BootstrapServers'"
}
if ($bootstrapUri -and $bootstrapUri.Port -gt 0) {
    $brokerReachable = Test-DemoTcpConnection `
        -HostName $bootstrapUri.Host `
        -Port $bootstrapUri.Port
    Write-Check "Kafka broker reachable at $BootstrapServers" $brokerReachable `
        "Broker is not up yet - run Start-Kafka.ps1 before Start-Demo.ps1" `
        -WarnOnly
}

Write-Host "`n=== Interactive GUI ===" -ForegroundColor Cyan
if ($platform.IsWindows) {
    Write-Check "Interactive desktop session" ([Environment]::UserInteractive) `
        "Run interactive mode from a desktop login" -WarnOnly
} elseif ($platform.IsMacOS) {
    $guiAvailable = (-not $env:SSH_CONNECTION -and
        $null -ne (Get-Command open -ErrorAction SilentlyContinue))
    Write-Check "macOS GUI session available" $guiAvailable `
        "Interactive mode requires a local GUI login; use headless mode over SSH" `
        -WarnOnly
} else {
    $guiAvailable = [bool]($env:DISPLAY -or $env:WAYLAND_DISPLAY)
    Write-Check "Linux GUI session available" $guiAvailable `
        "Interactive mode requires DISPLAY or WAYLAND_DISPLAY; use headless mode otherwise" `
        -WarnOnly
}

Write-Host ""
if ($warnings.Count -gt 0) {
    Write-Host "$($warnings.Count) warning(s):" -ForegroundColor Yellow
    $warnings | ForEach-Object { Write-Host " - $_" -ForegroundColor Yellow }
}
if ($failures.Count -gt 0) {
    Write-Host "$($failures.Count) failure(s):" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
    Write-Host "`nPrerequisite check FAILED." -ForegroundColor Red
    exit 1
}

Write-Host "Prerequisite check PASSED." -ForegroundColor Green
exit 0
