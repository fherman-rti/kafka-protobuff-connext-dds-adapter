#Requires -Version 5.1
<#
.SYNOPSIS
    Collects Routing Service, Kafka broker, publisher, and subscriber logs
    into a single timestamped archive for troubleshooting.

.PARAMETER OutputDir
    Directory to write the archive into. Defaults to demo\logs\collected.
#>
[CmdletBinding()]
param(
    [string]$OutputDir
)

$ErrorActionPreference = "Stop"
# $PSScriptRoot is not reliably available in param() default values in a
# script that also has #Requires, so resolve it here instead.
if (-not $OutputDir) {
    $OutputDir = Join-Path $PSScriptRoot "..\logs\collected"
}
$demoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$logsDir = Join-Path $demoRoot "logs"
$dockerDir = Join-Path $demoRoot "docker"

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$collectDir = Join-Path $OutputDir $timestamp
New-Item -ItemType Directory -Force -Path $collectDir | Out-Null

Write-Host "Collecting application logs..." -ForegroundColor Cyan
Get-ChildItem -Path $logsDir -Filter "*.log" -File -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-Item $_.FullName -Destination $collectDir
}

$demoStateFile = Join-Path $logsDir "demo-state.json"
if (Test-Path $demoStateFile) {
    Copy-Item $demoStateFile -Destination $collectDir
}

Write-Host "Collecting Kafka broker container logs..." -ForegroundColor Cyan
Push-Location $dockerDir
try {
    docker compose logs --no-color broker > (Join-Path $collectDir "kafka_broker.log") 2>&1
    docker compose ps > (Join-Path $collectDir "docker_compose_ps.txt") 2>&1
} catch {
    Write-Host "Could not collect Docker logs: $_" -ForegroundColor Yellow
} finally {
    Pop-Location
}

$resolvedConfig = Join-Path $demoRoot "config\shapesdemo_demo.xml"
if (Test-Path $resolvedConfig) {
    Copy-Item $resolvedConfig -Destination $collectDir
}

$archivePath = "$collectDir.zip"
Compress-Archive -Path (Join-Path $collectDir "*") -DestinationPath $archivePath -Force
Write-Host "`nLogs collected: $collectDir" -ForegroundColor Green
Write-Host "Archive created: $archivePath" -ForegroundColor Green
