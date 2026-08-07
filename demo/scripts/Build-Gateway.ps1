#Requires -Version 5.1
<#
.SYNOPSIS
    Configures, builds, installs, and validates the Gateway components needed
    by the Kafka/Protobuf Shapes demo on Windows x64, macOS ARM64, or Linux x64.
#>
[CmdletBinding()]
param(
    [string]$ConnextDir,
    [string]$ConnextArch,
    [string]$BuildDir,
    [string]$InstallDir
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "Demo.Common.ps1")

$platform = Get-DemoPlatformInfo
Assert-DemoSupportedPlatform -PlatformInfo $platform
$paths = Get-DemoPaths -ScriptRoot $PSScriptRoot
$ConnextDir = Resolve-DemoConnextDirectory -ConnextDir $ConnextDir -PlatformInfo $platform
$ConnextArch = Resolve-DemoConnextArchitecture `
    -ConnextDir $ConnextDir `
    -ConnextArch $ConnextArch `
    -PlatformInfo $platform

if (-not $InstallDir) {
    $InstallDir = $paths.GatewayInstall
}
if (-not $BuildDir) {
    $buildName = switch ($platform.Platform) {
        "Windows" { "b-windows" }
        "macOS"   { "b-macos" }
        "Linux"   { "b-linux" }
    }
    $BuildDir = Join-Path $paths.RepoRoot $buildName
}

foreach ($commandName in @("cmake")) {
    if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
        throw "$commandName is not available on PATH. Install it and open a new PowerShell window."
    }
}
if (-not $platform.IsWindows -and -not (Get-Command ninja -ErrorAction SilentlyContinue)) {
    throw "Ninja is not available on PATH. Install Ninja before building on $($platform.Platform)."
}
if ($platform.IsMacOS -and -not (Get-Command clang -ErrorAction SilentlyContinue)) {
    throw "Apple Clang is not available. Install the Xcode command-line developer tools."
}
if ($platform.IsLinux -and -not (Get-Command gcc -ErrorAction SilentlyContinue)) {
    throw "GCC is not available. Install the Ubuntu build-essential package."
}
if (-not (Test-Path -LiteralPath (Join-Path $paths.GatewaySource "CMakeLists.txt"))) {
    throw "Gateway source is missing from '$($paths.GatewaySource)'. Clone the complete demo repository."
}

$configureArgs = @(
    "-S", $paths.GatewaySource,
    "-B", $BuildDir,
    "-DCONNEXTDDS_DIR=$ConnextDir",
    "-DCONNEXTDDS_ARCH=$ConnextArch",
    "-DCMAKE_INSTALL_PREFIX=$InstallDir",
    "-DRTIGATEWAY_ENABLE_ALL=OFF",
    "-DRTIGATEWAY_ENABLE_KAFKA=ON",
    "-DRTIGATEWAY_ENABLE_TSFM_PROTOBUF=ON",
    "-DRTIGATEWAY_ENABLE_EXAMPLES=ON",
    "-DRTIGATEWAY_ENABLE_PROTOBUF_BUILD=ON",
    "-DRTIGATEWAY_ENABLE_TESTS=OFF",
    # Keep the installed demo self-contained instead of opportunistically
    # linking Homebrew/apt compression libraries found on the build host.
    "-DWITH_ZSTD=OFF",
    "-DENABLE_LZ4_EXT=OFF"
)

if ($platform.IsWindows) {
    $configureArgs += @("-G", "Visual Studio 17 2022", "-A", "x64")
} else {
    $configureArgs += @("-G", "Ninja", "-DCMAKE_BUILD_TYPE=Release")
    if ($platform.IsMacOS) {
        $configureArgs += "-DCMAKE_OSX_ARCHITECTURES=arm64"
    }
}

Write-Host "Platform: $($platform.Platform) $($platform.OSArchitecture) (process $($platform.ProcessArchitecture))" -ForegroundColor Cyan
Write-Host "Connext: $ConnextDir [$ConnextArch]" -ForegroundColor Cyan
Write-Host "Configuring the vendored Gateway source in $BuildDir..." -ForegroundColor Cyan
Invoke-DemoNativeCommand -FilePath "cmake" -ArgumentList $configureArgs `
    -FailureMessage "CMake configuration failed"

$buildArgs = @("--build", $BuildDir, "--target", "install")
if ($platform.IsWindows) {
    $buildArgs += @("--config", "Release")
}

Write-Host "Building and installing the Gateway demo components..." -ForegroundColor Cyan
Invoke-DemoNativeCommand -FilePath "cmake" -ArgumentList $buildArgs `
    -FailureMessage "Gateway build failed"

$requiredArtifacts = Get-DemoRequiredArtifacts `
    -GatewayInstallDir $InstallDir `
    -PlatformInfo $platform
$missingArtifacts = @($requiredArtifacts | Where-Object {
    -not (Test-Path -LiteralPath $_ -PathType Leaf)
})
if ($missingArtifacts.Count -gt 0) {
    throw "Build completed but required artifacts are missing:`n$($missingArtifacts -join "`n")"
}

if ($platform.IsMacOS) {
    $installedLibraries = @(Get-ChildItem -LiteralPath (Join-Path $InstallDir "lib") `
        -Filter "*.dylib" -File | Select-Object -ExpandProperty FullName)
    $nativeArtifacts = @($installedLibraries)
    $nativeArtifacts += @($requiredArtifacts | Where-Object {
        $_ -notlike "*.pbdesc"
    })
    $nativeArtifacts = @($nativeArtifacts | Sort-Object -Unique)

    foreach ($artifact in $nativeArtifacts) {
        $fileOutput = (& file $artifact 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0 -or $fileOutput -notmatch "arm64" -or $fileOutput -match "x86_64") {
            throw "Expected a native ARM64 artifact, but 'file' reported: $fileOutput"
        }

        $dependencyOutput = (& otool -L $artifact 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) {
            throw "otool could not inspect '$artifact': $dependencyOutput"
        }
        if ($dependencyOutput -match "/opt/homebrew|/usr/local|/opt/local") {
            throw "Artifact '$artifact' has a build-host package dependency:`n$dependencyOutput"
        }
    }

    $names = Get-DemoPlatformArtifacts -PlatformInfo $platform
    foreach ($pluginName in @($names.KafkaAdapter, $names.ProtobufTransformation)) {
        $pluginPath = Join-Path (Join-Path $InstallDir "lib") $pluginName
        $dependencyOutput = (& otool -L $pluginPath 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) {
            throw "otool could not inspect '$pluginPath': $dependencyOutput"
        }
        Write-Host ($dependencyOutput.TrimEnd())
    }
} elseif ($platform.IsLinux) {
    $runtimeEnvironment = Get-DemoRuntimeEnvironment `
        -GatewayInstallDir $InstallDir `
        -ConnextDir $ConnextDir `
        -ConnextArch $ConnextArch `
        -PlatformInfo $platform
    Set-DemoRuntimeEnvironment -RuntimeEnvironment $runtimeEnvironment

    $names = Get-DemoPlatformArtifacts -PlatformInfo $platform
    foreach ($pluginName in @($names.KafkaAdapter, $names.ProtobufTransformation)) {
        $pluginPath = Join-Path (Join-Path $InstallDir "lib") $pluginName
        $dependencyOutput = (& ldd $pluginPath 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0 -or $dependencyOutput -match "not found") {
            throw "Unresolved dependencies in '$pluginPath':`n$dependencyOutput"
        }
    }
}

Write-Host "Gateway build and installation completed: $InstallDir" -ForegroundColor Green
