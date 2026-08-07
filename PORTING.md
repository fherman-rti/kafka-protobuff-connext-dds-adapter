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
- Use the platform's native automation shell: PowerShell on Windows and Bash
  on macOS/Ubuntu.
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

Keep the tested PowerShell scripts for Windows. Use Bash for macOS and Ubuntu,
with shared Unix platform logic in `demo/scripts/demo-common.sh`. The Unix
scripts must run with the Bash supplied by macOS; installing PowerShell is not
a prerequisite. Keep platform branches limited to:

- CMake generator and compiler selection
- Connext installation and architecture discovery
- Executable and shared-library names
- Runtime library search paths
- Interactive terminal and GUI process launch
- Platform prerequisite checks

On Unix, prefer shell and operating-system utilities that are already present
on the supported baseline. The macOS path uses `plutil`, `ps`, `lsof`,
`osascript`, and `ditto`; the Ubuntu branch may use its baseline Python 3 for
JSON and ZIP handling. Do not add a second scripting-runtime installation just
for orchestration.

The intended platform matrix is:

| Concern | Windows x64 | macOS ARM64 | Ubuntu 22.04 x64 |
| --- | --- | --- | --- |
| Automation shell | PowerShell 5.1 or 7 | System `/bin/bash` | System Bash |
| Compiler | MSVC | Apple Clang | GCC 11 |
| CMake generator | Visual Studio | Unix Makefiles | Unix Makefiles |
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

The native Bash workflow now configures with Unix Makefiles and builds without
PowerShell or Ninja. `Build-Gateway.sh` completed configure, build, install,
ARM64 inspection, and dependency inspection on this host. The scripts run with
the system Bash 3.2 baseline.

`demo-common.sh` provides the shared macOS/Ubuntu foundation. Native Bash entry
points now exist for prerequisite checking, building, Kafka startup, demo
startup, owned-process cleanup, and support-bundle collection. The macOS
prerequisite run passed platform, Connext, license, toolchain, artifact,
dependency, runtime-path, port, and GUI checks. Its only failure was the absent
Docker installation. ZIP support-bundle generation and stale-state cleanup
were also exercised successfully.

Docker is not installed, so the Kafka image spike and end-to-end traffic tests
remain pending. A prior Routing Service launch reached Connext startup but was
stopped by participant-index exhaustion in the current host session; that
host-state issue is separate from plugin dependency loading and must be cleared
before the end-to-end phase. The new process launcher and live PID-ownership
path have not been executed in this restricted development session because
process-table access is outside the repository-only permission profile.

The existing `.ps1` files remain the Windows workflow. The `.sh` files are the
macOS workflow and the basis for the Ubuntu port. These changes are not final
installation instructions until Docker and clean-room end-to-end runs pass.

## Phase 1: Apple Silicon Feasibility Spike

Time-box this phase before refactoring all scripts.

### Environment checks

- Install CMake, Git, Docker Desktop, and Apple command-line developer tools.
  Use the system `/bin/bash`; PowerShell and Ninja are not required.
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
./demo/scripts/Build-Gateway.sh
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
cd demo/docker
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

Keep `Demo.Common.ps1` for the Windows workflow. Use
`demo/scripts/demo-common.sh` for shared macOS/Ubuntu helpers covering:

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

The native Unix entry points are:

1. `Build-Gateway.sh`
2. `Test-Prerequisites.sh`
3. `Start-Kafka.sh`
4. `Start-Demo.sh`
5. `Stop-Demo.sh`
6. `Collect-Logs.sh`

After each shared-script change, run the narrow Windows check that covers the
modified behavior.

## Phase 3: Cross-platform Build Script

Use `Build-Gateway.ps1` for Windows and `Build-Gateway.sh` for Unix platform
build settings:

### Windows

- Preserve Visual Studio 2022 and `-A x64`.
- Preserve the current default Connext path and architecture.
- Continue checking `.dll`, `.exe`, and descriptor artifacts.

### macOS

- Require a native ARM64 shell process.
- Use Unix Makefiles and Apple Clang.
- Set `CMAKE_OSX_ARCHITECTURES=arm64`.
- Use the verified Connext installation and architecture.
- Check `.dylib` plugins and extensionless example executables.
- Run `file` and `otool -L` validation or provide equivalent script checks.

### Ubuntu

- Require x64.
- Use Unix Makefiles and GCC.
- Use the verified Connext installation and architecture.
- Check `.so` plugins and extensionless example executables.
- Use `ldd` to reject unresolved dependencies.

Use separate build directories such as `b-windows`, `b-macos`, and `b-linux`
if the same checkout can be shared across systems. Keep one platform-neutral
install layout beneath `rticonnextdds-gateway/install` on each machine.

## Phase 4: Cross-platform Prerequisite Checks

Use `Test-Prerequisites.ps1` on Windows and `Test-Prerequisites.sh` on Unix to
verify:

- Supported OS and CPU architecture
- The supported native shell and process architecture
- Connext directory, architecture libraries, launchers, and license
- Compiler, CMake, and Make
- Installed Gateway artifacts for the current platform
- Docker CLI, daemon, and Compose v2
- Ports 9092 and 9021
- Kafka connectivity when the broker is already running
- GUI session availability for Shapes Demo
- Required runtime library paths

Use the platform helper for bounded TCP connectivity and listening-port checks;
do not add a scripting runtime solely for these probes.

Keep the existing behavior in which an absent broker is a warning before the
platform's `Start-Kafka` script runs.

## Phase 5: Kafka Startup

Keep `Start-Kafka.ps1` for Windows and use `Start-Kafka.sh` on Unix. Preserve:

- Running Compose from `demo/docker` without leaving the caller in that directory
- `docker compose` startup
- Broker health polling
- Explicit `Square` and `Circle` creation
- Retried metadata verification
- Optional Control Center profile

Required checks:

- The script passes `bash -n` with the system Bash on macOS and Ubuntu.
- Docker Desktop or Docker Engine can pull the pinned image.
- The broker advertises `localhost:9092` correctly to host processes.
- Control Center starts on the target architecture or has a documented
  emulation limitation.

## Phase 6: Demo Process Orchestration

Keep `Start-Demo.ps1` for Windows and use `Start-Demo.sh` for platform-specific
Unix executable names and runtime-library paths while preserving the current
demo sequence.

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

Implement macOS interactive launch through Terminal.app log views while the
native child processes remain directly owned by the startup shell. Implement
Ubuntu interactive launch only after the behavior works inside the VM desktop.
Keep process ownership independent of terminal window titles.

Do not depend on shell profile files to set library paths. Supply the required
environment directly to each child process. Prefer installed rpaths where the
build supports them reliably; otherwise set `DYLD_LIBRARY_PATH` on macOS and
`LD_LIBRARY_PATH` on Ubuntu for the launched process tree.

## Phase 7: Stop And Log Collection

Keep `Stop-Demo.ps1` for Windows. Update `Stop-Demo.sh` on Unix to:

- Read only the PIDs recorded by `Start-Demo.sh`.
- Verify a process still corresponds to the expected demo component before
  stopping it when practical.
- Attempt graceful termination before forced termination.
- Preserve `-SkipKafka` on Windows and `--skip-kafka` on Unix.
- Run Compose teardown from `demo/docker` on every platform.

Keep `Collect-Logs.ps1` for Windows. Use `Collect-Logs.sh` on Unix to preserve a
common support bundle containing:

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

Install CMake, Make, GCC, Git, Docker Engine, Compose v2, and the Linux x64
Connext DDS Professional 7.7.0 distribution. Ubuntu's system Bash and Python 3
provide the orchestration and JSON/ZIP support; PowerShell and Ninja are not
required.

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
| Platform logic becomes duplicated | Keep Windows helpers in `Demo.Common.ps1` and shared Unix helpers in `demo-common.sh` |

## Completion Definition

The port is complete when all three supported targets pass a clean-room build
and both demo directions using the shared scripts:

- Windows x64
- macOS Apple Silicon ARM64
- Ubuntu 22.04 x64 in VirtualBox

Each target must also support repeat startup, owned-process cleanup, and log
collection without undocumented manual steps.
