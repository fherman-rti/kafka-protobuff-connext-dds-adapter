#Requires -Version 5.1
<#
.SYNOPSIS
    Starts the demonstration Kafka broker and creates the Square and Circle
    topics used by the two integration directions.

.PARAMETER WithControlCenter
    Also start Confluent Control Center on port 9021.

.PARAMETER TimeoutSeconds
    How long to wait for the broker to report healthy before failing.
#>
[CmdletBinding()]
param(
    [switch]$WithControlCenter,
    [int]$TimeoutSeconds = 90
)

$ErrorActionPreference = "Stop"
$dockerDir = Resolve-Path (Join-Path $PSScriptRoot "..\docker")
$brokerContainer = "kafka-shapes-protobuf-broker"
$topics = @("Square", "Circle")

Push-Location $dockerDir
try {
    Write-Host "Starting Kafka broker (KRaft mode)..." -ForegroundColor Cyan
    if ($WithControlCenter) {
        docker compose --profile control-center up -d
    } else {
        docker compose up -d broker
    }
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose up failed with exit code $LASTEXITCODE"
    }

    Write-Host "Waiting for broker to become healthy (timeout ${TimeoutSeconds}s)..." -ForegroundColor Cyan
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $healthy = $false
    while ((Get-Date) -lt $deadline) {
        $status = docker inspect --format "{{.State.Health.Status}}" $brokerContainer 2>$null
        if ($status -eq "healthy") {
            $healthy = $true
            break
        }
        Start-Sleep -Seconds 2
    }
    if (-not $healthy) {
        Write-Host "Broker logs:" -ForegroundColor Yellow
        docker logs --tail 100 $brokerContainer
        throw "Broker did not become healthy within ${TimeoutSeconds}s. See logs above."
    }
    Write-Host "Broker is healthy." -ForegroundColor Green

    foreach ($topic in $topics) {
        Write-Host "Creating topic '$topic' (if not present)..." -ForegroundColor Cyan
        docker exec $brokerContainer kafka-topics `
            --bootstrap-server localhost:9092 `
            --create --if-not-exists `
            --topic $topic --partitions 1 --replication-factor 1
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create topic '$topic'"
        }
    }

    Write-Host "Verifying topics..." -ForegroundColor Cyan
    $existingTopics = docker exec $brokerContainer kafka-topics --bootstrap-server localhost:9092 --list
    foreach ($topic in $topics) {
        if ($existingTopics -notcontains $topic) {
            throw "Topic '$topic' was not found after creation. Existing topics: $existingTopics"
        }
        Write-Host "  - $topic OK" -ForegroundColor Green
    }

    Write-Host "`nKafka broker ready at localhost:9092 with topics: $($topics -join ', ')" -ForegroundColor Green
    if ($WithControlCenter) {
        Write-Host "Control Center available at http://localhost:9021" -ForegroundColor Green
    }
} finally {
    Pop-Location
}
