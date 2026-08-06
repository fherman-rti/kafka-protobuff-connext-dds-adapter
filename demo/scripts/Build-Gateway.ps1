#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ConnextDir = "C:\Program Files\rti_connext_dds-7.7.0",
    [string]$ConnextArch = "x64Win64VS2017"
)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$sourceDir = Join-Path $repoRoot "rticonnextdds-gateway"
$buildDir = Join-Path $sourceDir "build"
$installDir = Join-Path $sourceDir "install"

if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    throw "CMake is not available on PATH. Install CMake and open a new PowerShell window."
}
if (-not (Test-Path (Join-Path $sourceDir "CMakeLists.txt"))) {
    throw "Gateway source is missing from $sourceDir. Clone the complete demo repository."
}
if (-not (Test-Path $ConnextDir)) {
    throw "Connext DDS was not found at $ConnextDir. Pass -ConnextDir with the installed location."
}

Write-Host "Configuring the vendored Gateway source..." -ForegroundColor Cyan
& cmake -S $sourceDir -B $buildDir `
    -G "Visual Studio 17 2022" `
    -A x64 `
    "-DCONNEXTDDS_DIR=$ConnextDir" `
    "-DCONNEXTDDS_ARCH=$ConnextArch" `
    "-DCMAKE_INSTALL_PREFIX=$installDir" `
    -DRTIGATEWAY_ENABLE_ALL=OFF `
    -DRTIGATEWAY_ENABLE_KAFKA=ON `
    -DRTIGATEWAY_ENABLE_TSFM_PROTOBUF=ON `
    -DRTIGATEWAY_ENABLE_EXAMPLES=ON `
    -DRTIGATEWAY_ENABLE_PROTOBUF_BUILD=ON `
    -DRTIGATEWAY_ENABLE_TESTS=OFF
if ($LASTEXITCODE -ne 0) {
    throw "CMake configuration failed with exit code $LASTEXITCODE."
}

Write-Host "Building and installing the Gateway demo components..." -ForegroundColor Cyan
& cmake --build $buildDir --config Release --target install
if ($LASTEXITCODE -ne 0) {
    throw "Gateway build failed with exit code $LASTEXITCODE."
}

$requiredArtifacts = @(
    (Join-Path $installDir "lib\rtikafkaadapter.dll"),
    (Join-Path $installDir "lib\rtiprotobuftransf.dll"),
    (Join-Path $installDir "examples\kafka\kafka-shapes-protobuf\shape_type.pbdesc"),
    (Join-Path $installDir "examples\kafka\kafka-shapes-protobuf\bin\shapes_kafka_publisher.exe"),
    (Join-Path $installDir "examples\kafka\kafka-shapes-protobuf\bin\shapes_kafka_subscriber.exe")
)
$missingArtifacts = $requiredArtifacts | Where-Object { -not (Test-Path $_) }
if ($missingArtifacts) {
    throw "Build completed but required artifacts are missing:`n$($missingArtifacts -join "`n")"
}

Write-Host "Gateway build and installation completed: $installDir" -ForegroundColor Green