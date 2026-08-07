# Shared platform and process helpers for the demo scripts. Keep this file
# compatible with Windows PowerShell 5.1; Unix callers require PowerShell 7.

function Get-DemoPlatformInfo {
    $isWindowsHost = ($env:OS -eq "Windows_NT")

    if ($isWindowsHost) {
        $platform = "Windows"
        $processArchitecture = $env:PROCESSOR_ARCHITECTURE
        $osArchitecture = if ($env:PROCESSOR_ARCHITEW6432) {
            $env:PROCESSOR_ARCHITEW6432
        } else {
            $processArchitecture
        }
    } else {
        $kernelName = (& uname -s 2>$null | Out-String).Trim()
        $processArchitecture = (& uname -m 2>$null | Out-String).Trim()

        if ($kernelName -eq "Darwin") {
            $platform = "macOS"
            $armCapability = (& sysctl -n hw.optional.arm64 2>$null | Out-String).Trim()
            $osArchitecture = if ($armCapability -eq "1") {
                "arm64"
            } else {
                $processArchitecture
            }
        } elseif ($kernelName -eq "Linux") {
            $platform = "Linux"
            $osArchitecture = $processArchitecture
        } else {
            throw "Unsupported operating system '$kernelName'. This demo supports Windows, macOS, and Linux."
        }
    }

    [pscustomobject]@{
        Platform            = $platform
        OSArchitecture      = $osArchitecture
        ProcessArchitecture = $processArchitecture
        IsWindows           = ($platform -eq "Windows")
        IsMacOS             = ($platform -eq "macOS")
        IsLinux             = ($platform -eq "Linux")
    }
}

function Assert-DemoSupportedPlatform {
    param(
        [Parameter(Mandatory = $true)]
        $PlatformInfo
    )

    $osArch = $PlatformInfo.OSArchitecture.ToLowerInvariant()
    $processArch = $PlatformInfo.ProcessArchitecture.ToLowerInvariant()

    switch ($PlatformInfo.Platform) {
        "Windows" {
            if ($osArch -notmatch "x64|amd64") {
                throw "Windows must be x64. Detected OS architecture '$($PlatformInfo.OSArchitecture)'."
            }
        }
        "macOS" {
            if ($osArch -notmatch "arm64|aarch64") {
                throw "Intel macOS is not supported. An Apple Silicon ARM64 host is required."
            }
            if ($processArch -notmatch "arm64|aarch64") {
                throw "PowerShell is running under Rosetta ($($PlatformInfo.ProcessArchitecture)). Install and run native ARM64 PowerShell 7."
            }
            if ($PSVersionTable.PSVersion.Major -lt 7) {
                throw "macOS requires PowerShell 7 or newer."
            }
        }
        "Linux" {
            if ($osArch -notmatch "x64|amd64") {
                throw "Linux must be x64. Detected OS architecture '$($PlatformInfo.OSArchitecture)'."
            }
            if ($PSVersionTable.PSVersion.Major -lt 7) {
                throw "Linux requires PowerShell 7 or newer."
            }
        }
    }
}

function Get-DemoPaths {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptRoot
    )

    $demoRoot = [System.IO.Path]::GetFullPath((Join-Path $ScriptRoot ".."))
    $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $demoRoot ".."))
    $gatewaySource = Join-Path $repoRoot "rticonnextdds-gateway"

    [pscustomobject]@{
        RepoRoot       = $repoRoot
        DemoRoot       = $demoRoot
        GatewaySource  = $gatewaySource
        GatewayInstall = (Join-Path $gatewaySource "install")
        LogsDirectory  = (Join-Path $demoRoot "logs")
        ConfigDirectory = (Join-Path $demoRoot "config")
        DockerDirectory = (Join-Path $demoRoot "docker")
    }
}

function Resolve-DemoConnextDirectory {
    param(
        [string]$ConnextDir,

        [Parameter(Mandatory = $true)]
        $PlatformInfo
    )

    if ($ConnextDir) {
        if (-not (Test-Path -LiteralPath $ConnextDir -PathType Container)) {
            throw "Connext DDS was not found at '$ConnextDir'. Pass -ConnextDir with the installed location."
        }
        return (Resolve-Path -LiteralPath $ConnextDir).Path
    }

    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($environmentPath in @($env:NDDSHOME, $env:CONNEXTDDS_DIR)) {
        if ($environmentPath) {
            $candidates.Add($environmentPath)
        }
    }

    if ($PlatformInfo.IsWindows) {
        $candidates.Add("C:\Program Files\rti_connext_dds-7.7.0")
    } elseif ($PlatformInfo.IsMacOS) {
        $candidates.Add("/Applications/rti_connext_dds-7.7.0")
        Get-ChildItem -LiteralPath "/Applications" -Directory -Filter "rti_connext_dds-*" `
            -ErrorAction SilentlyContinue | ForEach-Object { $candidates.Add($_.FullName) }
    } else {
        $candidates.Add("/opt/rti_connext_dds-7.7.0")
        Get-ChildItem -LiteralPath "/opt" -Directory -Filter "rti_connext_dds-*" `
            -ErrorAction SilentlyContinue | ForEach-Object { $candidates.Add($_.FullName) }
    }

    $existing = @($candidates | Where-Object {
        $_ -and (Test-Path -LiteralPath $_ -PathType Container)
    } | ForEach-Object {
        (Resolve-Path -LiteralPath $_).Path
    } | Sort-Object -Unique)

    if ($existing.Count -eq 1) {
        return $existing[0]
    }
    if ($existing.Count -gt 1) {
        throw "Multiple Connext installations were found: $($existing -join ', '). Pass -ConnextDir explicitly."
    }

    throw "Connext DDS was not found. Pass -ConnextDir or set NDDSHOME to the installation directory."
}

function Resolve-DemoConnextArchitecture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConnextDir,

        [string]$ConnextArch,

        [Parameter(Mandatory = $true)]
        $PlatformInfo
    )

    $libRoot = Join-Path $ConnextDir "lib"
    if (-not (Test-Path -LiteralPath $libRoot -PathType Container)) {
        throw "Connext library directory is missing: $libRoot"
    }

    if ($ConnextArch) {
        $requestedDirectory = Join-Path $libRoot $ConnextArch
        if (-not (Test-Path -LiteralPath $requestedDirectory -PathType Container)) {
            throw "Connext architecture '$ConnextArch' is not installed under '$libRoot'."
        }
        return $ConnextArch
    }

    $architectures = @(Get-ChildItem -LiteralPath $libRoot -Directory | Where-Object {
        if ($PlatformInfo.IsWindows) {
            $_.Name -match "Win" -and $_.Name -match "x64"
        } elseif ($PlatformInfo.IsMacOS) {
            $_.Name -match "^arm64Darwin"
        } else {
            $_.Name -match "^x64Linux"
        }
    } | Select-Object -ExpandProperty Name)

    if ($architectures.Count -eq 1) {
        return $architectures[0]
    }
    if ($architectures.Count -gt 1) {
        throw "Multiple matching Connext architectures were found: $($architectures -join ', '). Pass -ConnextArch explicitly."
    }

    throw "No Connext architecture matching $($PlatformInfo.Platform)/$($PlatformInfo.OSArchitecture) was found under '$libRoot'. Pass -ConnextArch explicitly after verifying the installed target."
}

function Get-DemoPlatformArtifacts {
    param(
        [Parameter(Mandatory = $true)]
        $PlatformInfo
    )

    if ($PlatformInfo.IsWindows) {
        $sharedPrefix = ""
        $sharedSuffix = ".dll"
        $executableSuffix = ".exe"
        $launcherSuffix = ".bat"
    } elseif ($PlatformInfo.IsMacOS) {
        $sharedPrefix = "lib"
        $sharedSuffix = ".dylib"
        $executableSuffix = ""
        $launcherSuffix = ""
    } else {
        $sharedPrefix = "lib"
        $sharedSuffix = ".so"
        $executableSuffix = ""
        $launcherSuffix = ""
    }

    [pscustomobject]@{
        KafkaAdapter          = "${sharedPrefix}rtikafkaadapter${sharedSuffix}"
        ProtobufTransformation = "${sharedPrefix}rtiprotobuftransf${sharedSuffix}"
        Publisher             = "shapes_kafka_publisher${executableSuffix}"
        Subscriber            = "shapes_kafka_subscriber${executableSuffix}"
        RoutingServiceLauncher = "rtiroutingservice${launcherSuffix}"
        ShapesDemoLauncher    = "rtishapesdemo${launcherSuffix}"
        SharedLibrarySuffix   = $sharedSuffix
    }
}

function Get-DemoRequiredArtifacts {
    param(
        [Parameter(Mandatory = $true)]
        [string]$GatewayInstallDir,

        [Parameter(Mandatory = $true)]
        $PlatformInfo
    )

    $names = Get-DemoPlatformArtifacts -PlatformInfo $PlatformInfo
    $exampleDir = Join-Path $GatewayInstallDir "examples/kafka/kafka-shapes-protobuf"
    $exampleBinDir = Join-Path $exampleDir "bin"

    @(
        (Join-Path (Join-Path $GatewayInstallDir "lib") $names.KafkaAdapter),
        (Join-Path (Join-Path $GatewayInstallDir "lib") $names.ProtobufTransformation),
        (Join-Path $exampleDir "shape_type.pbdesc"),
        (Join-Path $exampleBinDir $names.Publisher),
        (Join-Path $exampleBinDir $names.Subscriber)
    )
}

function Get-DemoRuntimeEnvironment {
    param(
        [Parameter(Mandatory = $true)]
        [string]$GatewayInstallDir,

        [Parameter(Mandatory = $true)]
        [string]$ConnextDir,

        [Parameter(Mandatory = $true)]
        [string]$ConnextArch,

        [Parameter(Mandatory = $true)]
        $PlatformInfo
    )

    $gatewayLibDir = Join-Path $GatewayInstallDir "lib"
    $connextLibDir = Join-Path (Join-Path $ConnextDir "lib") $ConnextArch
    $separator = [System.IO.Path]::PathSeparator

    if ($PlatformInfo.IsWindows) {
        $variableName = "PATH"
    } elseif ($PlatformInfo.IsMacOS) {
        $variableName = "DYLD_LIBRARY_PATH"
    } else {
        $variableName = "LD_LIBRARY_PATH"
    }

    $currentValue = [System.Environment]::GetEnvironmentVariable($variableName, "Process")
    $parts = @($gatewayLibDir, $connextLibDir)
    if ($currentValue) {
        $parts += $currentValue
    }

    [pscustomobject]@{
        VariableName  = $variableName
        Value         = ($parts -join $separator)
        GatewayLibDir = $gatewayLibDir
        ConnextLibDir = $connextLibDir
    }
}

function Set-DemoRuntimeEnvironment {
    param(
        [Parameter(Mandatory = $true)]
        $RuntimeEnvironment
    )

    [System.Environment]::SetEnvironmentVariable(
        $RuntimeEnvironment.VariableName,
        $RuntimeEnvironment.Value,
        "Process"
    )
}

function Invoke-DemoNativeCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string[]]$ArgumentList = @(),

        [string]$FailureMessage = "Native command failed"
    )

    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "$FailureMessage with exit code $LASTEXITCODE."
    }
}

function Test-DemoTcpConnection {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,

        [Parameter(Mandatory = $true)]
        [int]$Port,

        [int]$TimeoutMilliseconds = 1000
    )

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $asyncResult = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $asyncResult.AsyncWaitHandle.WaitOne($TimeoutMilliseconds, $false)) {
            return $false
        }
        $client.EndConnect($asyncResult)
        return $true
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Test-DemoLocalPortAvailable {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Port
    )

    $listener = [System.Net.Sockets.TcpListener]::new(
        [System.Net.IPAddress]::Any,
        $Port
    )
    try {
        $listener.Server.ExclusiveAddressUse = $true
        $listener.Start()
        return $true
    } catch {
        return $false
    } finally {
        $listener.Stop()
    }
}
