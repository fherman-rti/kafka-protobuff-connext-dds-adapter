# macOS and Ubuntu Porting Plan

This document plans the port of the RTI Routing Service Kafka/Protobuf Shapes
demonstration from Windows to these targets:

- macOS on Apple Silicon ARM64
- Ubuntu 22.04 x64 running in a VirtualBox VM

Intel macOS is out of scope. Windows remains a supported platform and must not
regress as the scripts become cross-platform.

This is a porting plan, not a tested installation guide. Commands, Connext
architecture names, artifact names, and Docker image architecture support must
be verified on each target before they are promoted into the README or demo
playbook.

## Goals

- Build the Gateway Kafka adapter, Protobuf transformation, and Shapes example
  applications from the source included in this repository.
- Run the pinned Kafka broker through Docker Compose.
- Run Routing Service, Shapes Demo, and the example publisher and subscriber.
- Preserve the two demonstration paths:
  - DDS `Square` to Kafka `Square`
  - Kafka `Circle` to DDS `Circle`
- Keep one PowerShell 7 orchestration workflow where practical.
- Preserve the existing Windows clean-room workflow.

## Non-goals

- Supporting Intel macOS.
- Building the Kafka broker from source. The broker remains the pinned
  `confluentinc/cp-kafka:7.6.1` container image.
- Restricting Kafka itself to two topics. `Square` and `Circle` are the demo's
  application topics, not a broker-level whitelist.
- Replacing the current demo configuration or message format.
- Using the included upstream `tmux_session.sh` unchanged. It contains stale
  behavior and is only a reference for Unix environment setup.

## Porting Strategy

Use PowerShell 7 on all three operating systems. Extract shared platform logic
into `demo/scripts/Demo.Common.ps1`, then keep platform branches limited to:

- CMake generator and compiler selection
- Connext installation and architecture discovery
- Executable and shared-library names
- Runtime library search paths
- Interactive terminal and GUI process launch
- Platform prerequisite checks

Prefer .NET APIs from PowerShell for filesystem, networking, JSON, and process
operations. This avoids separate calls to Windows, Linux, and macOS utilities
when a portable API is available.

The intended platform matrix is:

| Concern | Windows x64 | macOS ARM64 | Ubuntu 22.04 x64 |
| --- | --- | --- | --- |
| PowerShell | 5.1 or 7 | 7 | 7 |
| Compiler | MSVC | Apple Clang | GCC 11 |
| CMake generator | Visual Studio | Ninja | Ninja |
| Shared library | `.dll` | `.dylib` | `.so` |
| Runtime library path | `PATH` | `DYLD_LIBRARY_PATH` or rpath | `LD_LIBRARY_PATH` or rpath |
| Docker runtime | Docker Desktop | Docker Desktop | Docker Engine |
| Connext architecture | Existing Windows value | Discover from install | Discover from install |

Do not guess Connext architecture directory names. Read them from the installed
Connext distribution and require an explicit override when discovery is
ambiguous.

## Work Order

Apple Silicon macOS is the first target because it has the greatest technical
uncertainty. Ubuntu follows after the shared Unix build and runtime path is
proven. Windows regression testing follows every shared-script milestone.

1. Apple Silicon feasibility spike
2. Shared script foundation
3. macOS build and end-to-end runtime
4. Ubuntu 22.04 VirtualBox build and runtime
5. Windows regression
6. Tested installation documentation

## Current macOS Status

Status recorded on 2026-08-07 from an Apple Silicon host running macOS 26.3
with Connext DDS Professional 7.7.0.

The native source-build feasibility gate is a **go**:

- The installed Connext target is `arm64Darwin23clang16.0`; its Routing
  Service libraries and Shapes Demo executable report native ARM64.
- The focused Gateway configuration completed with Apple Clang 21 and
  `CMAKE_OSX_ARCHITECTURES=arm64`.
- The Kafka adapter, Protobuf transformation, bundled dependencies,
  descriptor, publisher, and subscriber built and installed successfully.
- Every installed library and example executable inspected with `file`
  reports ARM64.
- `otool -L` inspection completed for both plugins, and a direct loader probe
  successfully loaded both plugins together using the planned
  `DYLD_LIBRARY_PATH` containing the Gateway and Connext library directories.

The initial spike used Unix Makefiles because Ninja and PowerShell 7 are not
installed on the host. The supported automation still requires those tools;
the script-driven Ninja build remains to be run after they are available.
Docker is also not installed, so the Kafka image spike and end-to-end traffic
tests remain pending. A full Routing Service launch reached Connext startup
but was stopped by participant-index exhaustion in the current host session;
that host-state issue is separate from plugin dependency loading and must be
cleared before the end-to-end phase.

Shared-script work is in progress: `Demo.Common.ps1`, `Build-Gateway.ps1`, and
`Test-Prerequisites.ps1` now contain the macOS ARM64 platform path while
preserving the Windows path. These changes are not installation instructions
until the PowerShell/Ninja workflow and clean-room run pass.

## Phase 1: Apple Silicon Feasibility Spike

Time-box this phase before refactoring all scripts.

### Environment checks

- Install PowerShell 7, CMake, Ninja, Git, Docker Desktop, and Apple command-line
  developer tools.
- Install Connext DDS Professional 7.7.0 for Apple Silicon, including Routing
  Service and Shapes Demo.
- Confirm a valid license through the installation or `RTI_LICENSE_FILE`.
- Confirm the installed Connext binaries and libraries are native ARM64.
- Record the actual Connext installation path and architecture directory.

Example probes to adapt to the installed layout:

```bash
uname -m
file "$NDDSHOME/bin/rtiroutingservice"
file "$NDDSHOME/bin/rtishapesdemo"
find "$NDDSHOME/lib" -maxdepth 2 -type f -name '*.dylib' | head
```

Expected host architecture: `arm64`.

### Source-build spike

Configure a clean native ARM64 build without changing the Windows build:

```bash
cmake -S rticonnextdds-gateway -B b-macos -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCONNEXTDDS_DIR="$NDDSHOME" \
  -DCONNEXTDDS_ARCH="<verified-installed-architecture>" \
  -DCMAKE_INSTALL_PREFIX="$PWD/rticonnextdds-gateway/install" \
  -DRTIGATEWAY_ENABLE_ALL=OFF \
  -DRTIGATEWAY_ENABLE_KAFKA=ON \
  -DRTIGATEWAY_ENABLE_TSFM_PROTOBUF=ON \
  -DRTIGATEWAY_ENABLE_EXAMPLES=ON \
  -DRTIGATEWAY_ENABLE_PROTOBUF_BUILD=ON \
  -DRTIGATEWAY_ENABLE_TESTS=OFF
cmake --build b-macos --target install
```

Inspect every produced plugin, dependency, and example executable:

```bash
file rticonnextdds-gateway/install/lib/*
otool -L rticonnextdds-gateway/install/lib/librtikafkaadapter.dylib
otool -L rticonnextdds-gateway/install/lib/librtiprotobuftransf.dylib
```

Acceptance criteria:

- CMake configures without using Rosetta or x86_64 dependencies.
- Gateway plugins and example applications build and install.
- Relevant binaries report `arm64`.
- `otool -L` reports resolvable ARM64 dependencies.
- Routing Service can load both plugins.

### Kafka image spike

Determine the architecture supplied for the pinned image before changing
Compose:

```bash
docker pull confluentinc/cp-kafka:7.6.1
docker image inspect confluentinc/cp-kafka:7.6.1 \
  --format '{{.Architecture}}/{{.Os}}'
```

Then run the existing Compose service and inspect the resulting container:

```bash
Set-Location demo/docker
docker compose up -d broker
docker inspect kafka-shapes-protobuf-broker \
  --format '{{.Platform}}'
```

If the image is AMD64-only, document Docker Desktop emulation as an explicit
runtime exception. Do not introduce x86_64 libraries into the native Gateway
build. Before replacing the image, verify compatibility, licensing, startup
commands, health checks, and Control Center behavior.

Phase 1 stops with a written go/no-go result. The critical gate is a native
ARM64 Gateway build that Routing Service can load.

## Phase 2: Shared Script Foundation

Create `demo/scripts/Demo.Common.ps1` with focused helpers for:

- OS and CPU architecture detection
- Supported-platform validation
- Repository-relative path resolution
- Connext installation discovery
- Connext architecture discovery and validation
- Platform-specific artifact names
- Runtime library path construction
- Native command execution and exit-code checking
- TCP port availability checks
- Process state serialization and cleanup

Reject Intel macOS early and clearly. Do not reject x64 Ubuntu or the existing
Windows target.

Update scripts incrementally:

1. `Build-Gateway.ps1`
2. `Test-Prerequisites.ps1`
3. `Start-Kafka.ps1`
4. `Start-Demo.ps1`
5. `Stop-Demo.ps1`
6. `Collect-Logs.ps1`

After each shared-script change, run the narrow Windows check that covers the
modified behavior.

## Phase 3: Cross-platform Build Script

Update `Build-Gateway.ps1` to select platform build settings:

### Windows

- Preserve Visual Studio 2022 and `-A x64`.
- Preserve the current default Connext path and architecture.
- Continue checking `.dll`, `.exe`, and descriptor artifacts.

### macOS

- Require PowerShell 7 and ARM64.
- Use Ninja and Apple Clang.
- Set `CMAKE_OSX_ARCHITECTURES=arm64`.
- Use the verified Connext installation and architecture.
- Check `.dylib` plugins and extensionless example executables.
- Run `file` and `otool -L` validation or provide equivalent script checks.

### Ubuntu

- Require PowerShell 7 and x64.
- Use Ninja and GCC.
- Use the verified Connext installation and architecture.
- Check `.so` plugins and extensionless example executables.
- Use `ldd` to reject unresolved dependencies.

Use separate build directories such as `b-windows`, `b-macos`, and `b-linux`
if the same checkout can be shared across systems. Keep one platform-neutral
install layout beneath `rticonnextdds-gateway/install` on each machine.

## Phase 4: Cross-platform Prerequisite Checks

Update `Test-Prerequisites.ps1` to verify:

- Supported OS and CPU architecture
- PowerShell version
- Connext directory, architecture libraries, launchers, and license
- Compiler, CMake, and Ninja
- Installed Gateway artifacts for the current platform
- Docker CLI, daemon, and Compose v2
- Ports 9092 and 9021
- Kafka connectivity when the broker is already running
- GUI session availability for Shapes Demo
- Required runtime library paths

Use `System.Net.Sockets` for portable port checks rather than
`Get-NetTCPConnection`, `ss`, or `lsof` where practical.

Keep the existing behavior in which an absent broker is a warning before
`Start-Kafka.ps1` runs.

## Phase 5: Kafka Startup

`Start-Kafka.ps1` is already mostly portable. Preserve:

- `Push-Location` and `Pop-Location`
- `docker compose` startup
- Broker health polling
- Explicit `Square` and `Circle` creation
- Retried metadata verification
- Optional Control Center profile

Required checks:

- PowerShell 7 parses the script on macOS and Ubuntu.
- Docker Desktop or Docker Engine can pull the pinned image.
- The broker advertises `localhost:9092` correctly to host processes.
- Control Center starts on the target architecture or has a documented
  emulation limitation.

## Phase 6: Demo Process Orchestration

Update `Start-Demo.ps1` to use platform-specific executable names and runtime
library paths while preserving the current demo sequence.

Shared behavior:

- Copy `shape_type.pbdesc` beside the Routing Service configuration.
- Set `KAFKA_BOOTSTRAP_SERVERS` and `DDS_DOMAIN_ID`.
- Start Routing Service from the demo configuration directory.
- Start the decoded `Square` subscriber.
- Stage the `Circle` publisher until the presenter presses Enter.
- Start Shapes Demo.
- Write owned process IDs to `demo/logs/demo-state.json`.
- Redirect process output to the current log files.

For the first Unix implementation, support two modes:

- Interactive presenter mode, with visible terminal windows and Shapes Demo
- Headless validation mode, without terminal-window dependencies

Implement macOS interactive launch through a tested Terminal.app or PowerShell
process strategy. Implement Ubuntu interactive launch only after the behavior
works inside the VM desktop. Keep process ownership independent of terminal
window titles.

Do not depend on shell profile files to set library paths. Supply the required
environment directly to each child process. Prefer installed rpaths where the
build supports them reliably; otherwise set `DYLD_LIBRARY_PATH` on macOS and
`LD_LIBRARY_PATH` on Ubuntu for the launched process tree.

## Phase 7: Stop And Log Collection

Update `Stop-Demo.ps1` to:

- Read only the PIDs recorded by `Start-Demo.ps1`.
- Verify a process still corresponds to the expected demo component before
  stopping it when practical.
- Attempt graceful termination before forced termination.
- Preserve `-SkipKafka`.
- Run Compose teardown from `demo/docker` on every platform.

Update `Collect-Logs.ps1` to preserve a common support bundle containing:

- Routing Service log
- Publisher and subscriber logs
- Kafka broker logs
- Compose status
- Demo state
- Resolved demo XML
- Platform, CPU architecture, Connext architecture, and tool versions

Continue producing ZIP archives so support bundles have one format across all
platforms.

## Phase 8: macOS End-to-end Validation

Run from a fresh Apple Silicon checkout:

1. Build and install all Gateway components.
2. Run prerequisite validation.
3. Start Kafka without Control Center.
4. Verify `Square` and `Circle`.
5. Start the demo in headless validation mode.
6. Verify DDS-to-Kafka samples decode on `Square`.
7. Verify Kafka-to-DDS samples arrive on `Circle`.
8. Run interactive mode with Shapes Demo.
9. Repeat Kafka startup with Control Center if its image is supported.
10. Stop the demo and collect logs.

Acceptance criteria:

- Application binaries and libraries are native ARM64.
- Routing Service loads both plugins without unresolved dependencies.
- Both message directions work.
- Shapes Demo runs natively and displays the expected traffic.
- Cleanup does not stop unrelated processes or containers.
- A second run succeeds without manual cleanup.

## Phase 9: Ubuntu 22.04 VirtualBox Port

### VM baseline

Use Ubuntu 22.04 Desktop x64 with:

- 4 virtual CPUs
- 8 GB RAM
- 50 GB dynamically allocated disk
- 128 MB video memory and 3D acceleration
- Guest Additions
- NAT networking for the first end-to-end test

Clone and build on the VM's native Linux filesystem, not a VirtualBox shared
folder. Shared folders can introduce permission, symlink, and case-sensitivity
differences.

Install PowerShell 7, CMake, Ninja, GCC, Git, Docker Engine, Compose v2, and
the Linux x64 Connext DDS Professional 7.7.0 distribution.

Add the VM user to the Docker group and verify Docker without `sudo` after a
new login.

### Initial network boundary

Run every component inside the VM first:

- Kafka containers
- Routing Service
- Publisher and subscriber
- Shapes Demo

This isolates application portability from VirtualBox multicast and
port-forwarding behavior.

After the local VM demo passes:

- Add NAT forwarding only when the host must access ports 9021 or 9092.
- Use bridged networking only when DDS participants must cross the VM boundary.
- Test DDS discovery explicitly across that boundary.
- Configure DDS discovery peers if VirtualBox multicast is unreliable.

### Ubuntu acceptance criteria

- Clean x64 source build and install succeeds.
- `ldd` reports no unresolved plugin dependencies.
- Broker and optional Control Center start.
- Both message directions work inside the VM.
- Shapes Demo works in the VM desktop.
- Stop and log collection behave like macOS and Windows.
- The same scripts accept Linux paths containing spaces.

## Phase 10: Windows Regression

After shared-script changes, repeat the existing Windows clean-room sequence:

1. Clean clone
2. Gateway build
3. Prerequisite check
4. Kafka startup with Control Center
5. End-to-end demo
6. Stop and log collection

Windows is not considered preserved based only on parsing or artifact checks.
The two message directions must still pass.

## Documentation Deliverables

After each target passes clean-room testing:

- Add tested prerequisites and installation commands to `README.md`.
- Keep OS-specific installation sections separate.
- Update `demo/playbook.md` with platform-labelled commands, or create tested
  platform playbooks if one document becomes difficult to follow.
- Record exact supported Connext architecture names.
- Record whether each Docker image is native or emulated on Apple Silicon.
- Document supported interactive and headless modes.
- Include troubleshooting for shared-library resolution and Docker startup.

Do not publish speculative commands from this plan as installation
instructions until they have passed on a clean target system.

## Principal Risks

| Risk | Mitigation |
| --- | --- |
| Connext 7.7.0 component unavailable for Apple Silicon | Verify before script refactoring; stop at the feasibility gate |
| Vendored dependency fails on ARM64 | Isolate with a direct CMake build and inspect the failing target |
| Kafka or Control Center image is AMD64-only | Document emulation or select a tested compatible pinned image |
| Mixed ARM64 and x86_64 macOS artifacts | Enforce `arm64`; validate every binary with `file` and `otool` |
| macOS loader cannot find plugin dependencies | Validate install names and rpaths; pass child-process environment explicitly |
| GUI process loses environment | Launch Shapes Demo through the controlled process tree and test Terminal/Finder differences |
| VirtualBox DDS discovery fails across host boundary | Prove all-in-VM behavior first; then test bridged networking or discovery peers |
| Cross-platform refactor breaks Windows | Run narrow Windows checks after each script change and a final clean-room test |
| Platform logic becomes duplicated | Keep platform metadata and helpers in `Demo.Common.ps1` |

## Completion Definition

The port is complete when all three supported targets pass a clean-room build
and both demo directions using the shared scripts:

- Windows x64
- macOS Apple Silicon ARM64
- Ubuntu 22.04 x64 in VirtualBox

Each target must also support repeat startup, owned-process cleanup, and log
collection without undocumented manual steps.
