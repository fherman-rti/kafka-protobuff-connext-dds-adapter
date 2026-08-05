#Requires -Version 5.1
<#
.SYNOPSIS
    Stops only the processes and containers started by Start-Kafka.ps1 and
    Start-Demo.ps1 for this demonstration.

.DESCRIPTION
    Reads logs\demo-state.json (written by Start-Demo.ps1) and stops each
    recorded process ID, then brings down the demo's Docker Compose project.
    Does not touch unrelated Routing Service, Shapes Demo, or Kafka instances
    that were not started by these scripts.
#>
[CmdletBinding()]
param(
    [switch]$SkipKafka
)

$ErrorActionPreference = "Continue"
$demoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$logsDir = Join-Path $demoRoot "logs"
$stateFile = Join-Path $logsDir "demo-state.json"
$dockerDir = Join-Path $demoRoot "docker"

if (Test-Path $stateFile) {
    $state = Get-Content $stateFile -Raw | ConvertFrom-Json
    foreach ($entry in $state.processes.PSObject.Properties) {
        $procId = $entry.Value
        $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
        if ($proc) {
            Write-Host "Stopping $($entry.Name) (PID $procId, $($proc.ProcessName))..." -ForegroundColor Cyan
            Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
        } else {
            Write-Host "$($entry.Name) (PID $procId) is not running." -ForegroundColor Yellow
        }
    }
    Remove-Item $stateFile -Force
} else {
    Write-Host "No demo-state.json found; nothing to stop from Start-Demo.ps1." -ForegroundColor Yellow
}

if (-not $SkipKafka) {
    Write-Host "Stopping Kafka broker (and Control Center, if running)..." -ForegroundColor Cyan
    Push-Location $dockerDir
    try {
        docker compose --profile control-center down
    } finally {
        Pop-Location
    }
} else {
    Write-Host "Skipping Kafka broker shutdown (-SkipKafka)." -ForegroundColor Yellow
}

Write-Host "`nDemo stopped." -ForegroundColor Green
