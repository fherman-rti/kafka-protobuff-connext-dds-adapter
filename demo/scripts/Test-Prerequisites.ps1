#Requires -Version 5.1
<#
.SYNOPSIS
    Validates prerequisites for the RTI Routing Service Kafka/Protobuf shapes
    demonstration before any build or launch step is attempted.

.DESCRIPTION
    Checks, in order: Connext installation and architecture, license
    availability, Gateway build artifacts, Docker installation/daemon state,
    required ports, and (if the broker is already running) connectivity.
    Exits with a non-zero code and an actionable message on the first
    hard failure category, but reports all checks before deciding pass/fail
    so a single run shows the full picture.

.PARAMETER ConnextDir
    Path to the RTI Connext DDS installation.

.PARAMETER ConnextArch
    Connext target architecture matching the installed libraries.

.PARAMETER GatewayInstallDir
    Path to the Gateway CMake install output (contains lib/ and examples/).

.PARAMETER BootstrapServers
    Kafka bootstrap servers string, used only if the broker is already up.
#>
[CmdletBinding()]
param(
    [string]$ConnextDir = "C:\Program Files\rti_connext_dds-7.7.0",
    [string]$ConnextArch = "x64Win64VS2017",
    [string]$GatewayInstallDir,
    [string]$BootstrapServers = "localhost:9092"
)

$ErrorActionPreference = "Stop"
# $PSScriptRoot is not reliably available in param() default values in a
# script that also has #Requires, so resolve it here instead.
if (-not $GatewayInstallDir) {
    $GatewayInstallDir = Join-Path $PSScriptRoot "..\..\rticonnextdds-gateway\install"
}
$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Write-Check {
    param([string]$Name, [bool]$Ok, [string]$Detail = "", [switch]$WarnOnly)
    if ($Ok) {
        Write-Host "[ OK ] $Name" -ForegroundColor Green
    } elseif ($WarnOnly) {
        Write-Host "[WARN] $Name - $Detail" -ForegroundColor Yellow
        $warnings.Add("$Name - $Detail") | Out-Null
    } else {
        Write-Host "[FAIL] $Name - $Detail" -ForegroundColor Red
        $failures.Add("$Name - $Detail") | Out-Null
    }
}

Write-Host "=== Connext DDS installation ===" -ForegroundColor Cyan
$routingServiceBat = Join-Path $ConnextDir "bin\rtiroutingservice.bat"
$shapesDemoBat = Join-Path $ConnextDir "bin\rtishapesdemo.bat"
$connextLibDir = Join-Path $ConnextDir "lib\$ConnextArch"

Write-Check "Connext directory exists ($ConnextDir)" (Test-Path $ConnextDir)
Write-Check "RTI Routing Service launcher present" (Test-Path $routingServiceBat) `
    "Expected $routingServiceBat"
Write-Check "RTI Shapes Demo launcher present" (Test-Path $shapesDemoBat) `
    "Expected $shapesDemoBat"
Write-Check "Connext architecture libraries present ($ConnextArch)" (Test-Path $connextLibDir) `
    "Expected $connextLibDir - verify -DCONNEXTDDS_ARCH matches an installed architecture"

Write-Host "`n=== License ===" -ForegroundColor Cyan
$licenseCandidates = @(
    $env:RTI_LICENSE_FILE,
    (Join-Path $ConnextDir "rti_license.dat"),
    (Join-Path $env:USERPROFILE "rti_license.dat")
) | Where-Object { $_ }
$licenseFound = $licenseCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($licenseFound) {
    Write-Check "License file found ($licenseFound)" $true
} else {
    Write-Check "License file found" $false `
        "Set RTI_LICENSE_FILE or place rti_license.dat under $ConnextDir; a license server may also be used" `
        -WarnOnly
}

Write-Host "`n=== Gateway build artifacts ===" -ForegroundColor Cyan
$exampleDir = Join-Path $GatewayInstallDir "examples\kafka\kafka-shapes-protobuf"
$requiredArtifacts = @(
    (Join-Path $GatewayInstallDir "lib\rtikafkaadapter.dll"),
    (Join-Path $GatewayInstallDir "lib\rtiprotobuftransf.dll"),
    (Join-Path $exampleDir "shape_type.pbdesc"),
    (Join-Path $exampleDir "bin\shapes_kafka_publisher.exe"),
    (Join-Path $exampleDir "bin\shapes_kafka_subscriber.exe")
)
foreach ($artifact in $requiredArtifacts) {
    Write-Check "Build artifact present" (Test-Path $artifact) `
        "Missing $artifact - run the CMake build/install step from the README's Build plan"
}

Write-Host "`n=== Docker ===" -ForegroundColor Cyan
$dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
Write-Check "Docker CLI available" ($null -ne $dockerCmd) "Install Docker Desktop / Docker Engine"
if ($dockerCmd) {
    # Docker writes to stderr on failure, which PowerShell turns into a
    # terminating NativeCommandError under $ErrorActionPreference = "Stop".
    # Run these probes with errors treated as non-terminating.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    docker info *> $null
    $dockerInfoOk = ($LASTEXITCODE -eq 0)
    docker compose version *> $null
    $dockerComposeOk = ($LASTEXITCODE -eq 0)
    $ErrorActionPreference = $prevEap

    Write-Check "Docker daemon reachable" $dockerInfoOk `
        "Start Docker Desktop (or the Docker service) before running Start-Kafka.ps1"
    Write-Check "Docker Compose plugin available" $dockerComposeOk `
        "Docker Compose v2 (docker compose) is required"
}

Write-Host "`n=== Ports ===" -ForegroundColor Cyan
foreach ($port in @(9092, 9021)) {
    $inUse = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if ($inUse) {
        $owningProcesses = ($inUse.OwningProcess | Sort-Object -Unique | ForEach-Object {
            try { (Get-Process -Id $_).ProcessName } catch { "pid $_" }
        }) -join ", "
        if ($owningProcesses -match "com\.docker|docker") {
            Write-Check "Port $port free or owned by Docker" $true
        } else {
            Write-Check "Port $port free" $false `
                "Already in use by: $owningProcesses" -WarnOnly
        }
    } else {
        Write-Check "Port $port free" $true
    }
}

Write-Host "`n=== Broker connectivity (only if already running) ===" -ForegroundColor Cyan
$brokerHost, $brokerPort = $BootstrapServers.Split(":")
$tcpTest = Test-NetConnection -ComputerName $brokerHost -Port $brokerPort -WarningAction SilentlyContinue
if ($tcpTest.TcpTestSucceeded) {
    Write-Check "Kafka broker reachable at $BootstrapServers" $true
} else {
    Write-Check "Kafka broker reachable at $BootstrapServers" $false `
        "Broker is not up yet - run Start-Kafka.ps1 before Start-Demo.ps1" -WarnOnly
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
