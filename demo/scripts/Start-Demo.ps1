#Requires -Version 5.1
<#
.SYNOPSIS
    Launches the Kafka/Protobuf shapes demonstration: Routing Service, the
    decoded Kafka subscriber (Square), the Kafka publisher (Circle), and
    Shapes Demo, each in its own readable window.

.DESCRIPTION
    Assumes the Kafka broker and topics are already started (Start-Kafka.ps1)
    and that the Gateway build/install step from the README has completed.
    Process IDs and the Kafka broker bootstrap servers are recorded to
    logs\demo-state.json so Stop-Demo.ps1 can shut down only what this script
    started.

.PARAMETER ConnextDir
    Path to the RTI Connext DDS installation.

.PARAMETER ConnextArch
    Connext target architecture matching the installed libraries.

.PARAMETER GatewayInstallDir
    Path to the Gateway CMake install output (contains lib/ and examples/).

.PARAMETER BootstrapServers
    Kafka bootstrap.servers value used by Routing Service and the example apps.

.PARAMETER DomainId
    DDS domain ID used by Routing Service's DDS participant.

.PARAMETER CircleColor
    Shape color used by the Kafka publisher on the Circle topic.
#>
[CmdletBinding()]
param(
    [string]$ConnextDir = "C:\Program Files\rti_connext_dds-7.7.0",
    [string]$ConnextArch = "x64Win64VS2017",
    [string]$GatewayInstallDir,
    [string]$BootstrapServers = "localhost:9092",
    [int]$DomainId = 0,
    [string]$CircleColor = "GREEN"
)

$ErrorActionPreference = "Stop"
# $PSScriptRoot is not reliably available in param() default values in a
# script that also has #Requires, so resolve it here instead.
if (-not $GatewayInstallDir) {
    $GatewayInstallDir = Join-Path $PSScriptRoot "..\..\rticonnextdds-gateway\install"
}
$demoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$logsDir = Join-Path $demoRoot "logs"
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null

$exampleDir = Join-Path $GatewayInstallDir "examples\kafka\kafka-shapes-protobuf"
$exampleBinDir = Join-Path $exampleDir "bin"
$connextLibDir = Join-Path $ConnextDir "lib\$ConnextArch"
$configDir = Join-Path $demoRoot "config"
$rsConfigFile = Join-Path $configDir "shapesdemo_demo.xml"

$requiredPaths = @(
    (Join-Path $ConnextDir "bin\rtiroutingservice.bat"),
    (Join-Path $ConnextDir "bin\rtishapesdemo.bat"),
    $connextLibDir,
    (Join-Path $GatewayInstallDir "lib\rtikafkaadapter.dll"),
    (Join-Path $GatewayInstallDir "lib\rtiprotobuftransf.dll"),
    (Join-Path $exampleDir "shape_type.pbdesc"),
    (Join-Path $exampleBinDir "shapes_kafka_publisher.exe"),
    (Join-Path $exampleBinDir "shapes_kafka_subscriber.exe"),
    $rsConfigFile
)
foreach ($path in $requiredPaths) {
    if (-not (Test-Path $path)) {
        throw "Missing required path: $path. Run Test-Prerequisites.ps1 for details."
    }
}

# Keep the descriptor file adjacent to the demo XML, as the plan requires.
Copy-Item (Join-Path $exampleDir "shape_type.pbdesc") $configDir -Force

# Gateway plugin DLLs and the matching Connext libraries must be on PATH
# before Routing Service starts.
$env:PATH = "$(Join-Path $GatewayInstallDir 'lib');$connextLibDir;$env:PATH"
$env:KAFKA_BOOTSTRAP_SERVERS = $BootstrapServers
$env:DDS_DOMAIN_ID = "$DomainId"

$routingServiceBat = Join-Path $ConnextDir "bin\rtiroutingservice.bat"
$shapesDemoBat = Join-Path $ConnextDir "bin\rtishapesdemo.bat"
$subscriberExe = Join-Path $exampleBinDir "shapes_kafka_subscriber.exe"
$publisherExe = Join-Path $exampleBinDir "shapes_kafka_publisher.exe"

function Start-DemoWindow {
    param([string]$Title, [string]$Command, [string]$LogFile)
    $wrapped = "`$Host.UI.RawUI.WindowTitle = '$Title'; $Command *>&1 | Tee-Object -FilePath '$LogFile'"
    Start-Process -FilePath "powershell.exe" `
        -ArgumentList @("-NoExit", "-NoProfile", "-Command", $wrapped) `
        -WorkingDirectory $configDir `
        -PassThru
}

Write-Host "Starting Routing Service..." -ForegroundColor Cyan
$rsProc = Start-DemoWindow -Title "Routing Service" `
    -Command "& '$routingServiceBat' -cfgFile '$rsConfigFile' -cfgName shapesdemo_bridge" `
    -LogFile (Join-Path $logsDir "routing_service.log")
Start-Sleep -Seconds 3

Write-Host "Starting decoded Kafka subscriber on topic 'Square'..." -ForegroundColor Cyan
$subProc = Start-DemoWindow -Title "Kafka Subscriber (Square)" `
    -Command "& '$subscriberExe' '$BootstrapServers' Square" `
    -LogFile (Join-Path $logsDir "kafka_subscriber.log")

Write-Host "Staging Kafka publisher window for '$CircleColor' circles on topic 'Circle'..." -ForegroundColor Cyan
# Per the demonstration sequence, the Circle publisher is started live (after
# BLUE squares are already visible), not immediately. The window opens ready
# to go and waits for the presenter to press Enter.
$pubProc = Start-DemoWindow -Title "Kafka Publisher (Circle) - press Enter to start" `
    -Command "Read-Host 'Press Enter to start publishing $CircleColor circles to Kafka topic Circle'; & '$publisherExe' '$BootstrapServers' $CircleColor Circle" `
    -LogFile (Join-Path $logsDir "kafka_publisher.log")

Write-Host "Starting Shapes Demo..." -ForegroundColor Cyan
$shapesProc = Start-Process -FilePath $shapesDemoBat -PassThru

$state = [ordered]@{
    startedAt        = (Get-Date).ToString("o")
    bootstrapServers = $BootstrapServers
    domainId         = $DomainId
    processes        = [ordered]@{
        routingService   = $rsProc.Id
        kafkaSubscriber  = $subProc.Id
        kafkaPublisher   = $pubProc.Id
        shapesDemo       = $shapesProc.Id
    }
}
$stateFile = Join-Path $logsDir "demo-state.json"
$state | ConvertTo-Json | Set-Content -Path $stateFile -Encoding UTF8

Write-Host "`nAll demo processes started. State recorded in $stateFile." -ForegroundColor Green
Write-Host "In Shapes Demo: subscribe to Circle, then publish a BLUE Square." -ForegroundColor Green
Write-Host "Run Stop-Demo.ps1 when finished." -ForegroundColor Green
