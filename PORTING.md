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
| Container runtime | Docker Desktop | Docker-compatible macOS runtime | Docker Engine |
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
dependency, runtime-path, port, GUI, Docker-engine, and Compose checks. ZIP
support-bundle generation and stale-state cleanup were also exercised
successfully.

OrbStack 2.2.3 passed the Kafka container spike with its bundled Docker 29.4.0
client, Docker Engine 29.4.0 (`linux/arm64`), and Compose v5.1.2. The pinned
`confluentinc/cp-kafka:7.6.1` image pulled and started, its health check passed,
host port 9092 was reachable, and `Square` and `Circle` were created. A second
startup was idempotent. Compose teardown removed the broker and project network,
and OrbStack released the host port after its short asynchronous cleanup delay.
This particular OrbStack installation did not automatically expose `docker`
and its Compose plugin on the login shell `PATH`, so the validation used the
bundled tools directly. A clean-room run must confirm `docker version` and
`docker compose version` work normally before invoking the repository scripts;
the repository must not install or patch a user's container runtime.

Connext 7.7 enables Distributed Logger and Monitoring Library 2.0 by default;
the port must preserve both features. Routing Service and Shapes Demo both
reported an observability-participant failure on domain 101. The failure also
reproduced when Shapes was launched with RTI's stock macOS wrapper and default
workspace, so it is not caused by the repository's XML or isolated workspace.
Earlier stock-workspace logs show Connext failing to allocate its shared-memory
receive resources before reporting `No index available for participant`.

The host's System V settings were `shmmax=16777216`, `shmmni=32`, `shmseg=8`,
and `shmall=4096`, with no stale segments present. RTI documents this exact
macOS participant-index failure and recommends at least `shmmax=419430400`,
`shmmni=128`, `shmseg=1024`, and `shmall=262144`. The Unix prerequisite script
now rejects insufficient macOS settings instead of disabling observability.
`Start-Demo.sh` performs the same guard before starting any process. Applying
the host settings requires administrator access and a reboot and remains a
clean-room host prerequisite; see <https://community.rti.com/kb/osx510>.

RTI's Catalina-and-later `memory.plist` was installed as a root-owned launch
daemon on this validation host. Before reboot, macOS applied `shmmax=419430400`,
`shmseg=1024`, and `shmall=262144`, but rejected the live
`kern.sysv.shmmni=128` write with `Operation not permitted`; System Integrity
Protection is enabled. After reboot, all four settings report RTI's recommended
values: `shmmax=419430400`, `shmmni=128`, `shmseg=1024`, and `shmall=262144`.
The `shmemsetup` launch daemon reports one run with exit code 0, and the complete
Unix prerequisite check passes (with only the expected warning that Kafka is
not yet running). Stock Shapes Demo then started on domain 101 without displaying
the previous observability QoS error. The macOS shared-memory host prerequisite
is therefore complete. The subsequent repository-managed interactive run also
passed as described below.

The Windows launcher uses RTI's `rtishapesdemo.bat` and normal user workspace.
The macOS launcher starts the wrapper's embedded app executable with equivalent
template/workspace arguments, but uses an isolated demo workspace so the script
can own the real GUI PID and avoid inheriting user state. This process-ownership
difference did not cause the QoS failure. Both launchers now pass the selected
DDS domain explicitly. The Unix runtime setup also exports `NDDSHOME` and
`CONNEXTDDS_DIR` because Shapes' installed QoS XML references `$(NDDSHOME)`.

During diagnosis, a temporary process-scoped Monitoring override allowed
repeated headless launches to load the Kafka adapter and Protobuf transformation
and create both routes. That override has been removed from the port. An exact-
type, native ARM64 DynamicData probe completed both traffic directions on DDS
domain 64:

- Kafka `Circle` to DDS delivered a sample with `color=GREEN`.
- DDS `Square` to Kafka decoded all 12 probe samples with `color=BLUE` and the
  expected `x`, `y`, and `shapesize` values.

DDS Spy also discovered the native `ShapeType` writer with the expected
`Circle` topic and type definition. The probe was a temporary validation tool,
not a new runtime prerequisite or repository artifact.

The native process launcher and live PID ownership checks were exercised with
real Routing Service, publisher, and subscriber processes. Cleanup stopped only
the recorded matching processes, removed valid state, and repeated
successfully. Routing Service currently reports
`DDS_OctetSeq_set_maximum:failed to assert buffer must not be loaned` while the
Kafka reader is disabled during shutdown; startup and message processing still
succeed, but this adapter cleanup diagnostic remains to be investigated.

Interactive traffic through Shapes Demo passed on domain 101 with the documented
shared-memory settings. A Shapes `Circle` subscription displayed varying GREEN
circles produced through Kafka, and the decoded Kafka subscriber received BLUE
`Square` samples published from Shapes. Routing Service, Shapes, the publisher,
and the subscriber remained running with empty error logs during the test. The
macOS launcher now activates Terminal when it creates the Routing Service,
Kafka subscriber, and Kafka publisher log viewers. Exactly one active viewer for
each component was confirmed. Cleanup stopped only the recorded processes,
closed the three inactive demo log windows without touching unrelated Terminal
windows, removed the state file, and removed the broker container and Compose
network. A support bundle for the successful traffic run was captured under
`demo/logs/collected/20260807-174349.zip`.

The optional Control Center profile also started successfully through the normal
OrbStack Docker CLI, and its browser console was accessible on host port 9021.
A complete isolated-checkout rehearsal then passed from commit `7f62275` with
the current porting diff applied and no prior build or install directories. The
workflow completed a clean native ARM64 configure, build, install, artifact and
dependency inspection, and prerequisite check. It started Kafka and Control
Center, created both topics, served the Control Center UI on port 9021, decoded
a BLUE `Square` from Shapes on Kafka, and displayed varying GREEN `Circle`
samples from Kafka in Shapes. All four application error logs remained empty.
Final cleanup stopped only the recorded processes, closed exactly the three
inactive demo log windows, and removed both containers and the Compose network.
The clean-room support bundle is preserved as
`demo/logs/collected/20260807-175808-fresh-checkout.zip`.

The existing `.ps1` files remain the Windows workflow. The `.sh` files are the
macOS workflow and the basis for the Ubuntu port. The tested macOS setup and
demo commands have been promoted to [MACOS.md](MACOS.md). This document remains
the engineering record and plan for the remaining cross-platform and Windows
regression work.

## Current Ubuntu Implementation Status

Status recorded on 2026-08-10. The shared Bash workflow implements the Ubuntu
22.04 x64 build, prerequisite, Docker Compose, runtime environment, owned-
process cleanup, and support-bundle paths. Interactive startup now uses GNOME
Terminal for the Routing Service and decoded subscriber log viewers and for the
Enter-gated Kafka publisher. Shapes Demo is launched directly with the same
isolated workspace and explicit DDS domain used on macOS. Application process
ownership remains independent of terminal windows and titles.

The launcher rejects interactive use without a desktop display or GNOME
Terminal and continues to support `--headless` for SSH and process-only runs.
Docker Engine and the Compose v2 plugin remain the Ubuntu container runtime.

The implementation passes Bash syntax validation on Linux. An Ubuntu 22.04
VirtualBox clean-room run configured, compiled, and installed the complete
Gateway target with Connext architecture `x64Linux4gcc8.5.0`. The first
post-build inspection exposed a script defect: `file` inspected the installed
`.so` symlink instead of its ELF target. Native validation now uses `file -L`
and passes a focused ELF-symlink probe. A second issue occurred when `ldd`
inspected `librdkafka++.so` without the sibling Gateway install directory in
its search path. Dependency validation now supplies the same Gateway and
Connext library directories used at runtime. The corrected native and `ldd`
checks pass against every installed `.so` link and both example executables
from the clean-room build. The clean-room run completed Docker Engine broker
startup, the Connext GUI launch, and both traffic directions: the decoded Kafka
subscriber received BLUE `Square` samples from Shapes Demo, and Shapes Demo
displayed GREEN `Circle` samples produced through Kafka. An initial shutdown
also left the staged Kafka publisher's
GNOME Terminal window open because only the publisher application was recorded.
The launcher now records the terminal's Bash process with the same PID, start-
marker, and executable ownership data used for application processes, and
cleanup explicitly stops that owned process. A live retest showed that this was
not sufficient: both the publisher and Routing Service windows could retain
their `tail -f` children through Kafka teardown. All Linux viewers now watch a
shared demo-owned stop signal and use shell exit traps to terminate their tail
processes. `Stop-Demo.sh` asserts that signal before stopping applications or
containers and leaves it present until the next launcher removes it, avoiding
a viewer-observation race. A final clean-room retest passed installation,
startup, both demo directions, and shutdown; all four demo windows closed and
the broker and Compose network were removed. Linux process ownership checks now
use `/proc/<pid>/exe` so long executable names are not truncated by `ps` during
cleanup. The tested workflow is documented in [UBUNTU.md](UBUNTU.md).

## Phase 1: Apple Silicon Feasibility Spike

Time-box this phase before refactoring all scripts.

### Environment checks

- Install CMake, Git, a Docker-compatible macOS container runtime, and Apple
  command-line developer tools. Use the system `/bin/bash`; PowerShell and
  Ninja are not required.
- Install Connext DDS Professional 7.7.0 for Apple Silicon, including Routing
  Service and Shapes Demo.
- Confirm a valid license through the installation or `RTI_LICENSE_FILE`.
- Confirm the installed Connext binaries and libraries are native ARM64.
- Apply RTI's recommended macOS System V shared-memory settings and reboot.
- Record the actual Connext installation path and architecture directory.

Example probes to adapt to the installed layout:

```bash
uname -m
file "$NDDSHOME/bin/rtiroutingservice"
file "$NDDSHOME/bin/rtishapesdemo"
find "$NDDSHOME/lib" -maxdepth 2 -type f -name '*.dylib' | head
sysctl kern.sysv.shmmax kern.sysv.shmmni kern.sysv.shmseg kern.sysv.shmall
```

Expected host architecture: `arm64`.

`Test-Prerequisites.sh` reports the detected shared-memory settings and fails
before demo startup when they are below RTI's recommendations. Use RTI's
[macOS shared-memory instructions](https://community.rti.com/kb/osx510) for
the administrator-owned configuration; repository scripts do not change
kernel settings.

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

If the image is AMD64-only, document the selected runtime's emulation as an
explicit exception. Do not introduce x86_64 libraries into the native Gateway
build. Before replacing the image, verify compatibility, licensing, startup
commands, health checks, and Control Center behavior.

### macOS container-runtime candidates

The demo scripts intentionally target the `docker` CLI and Compose v2
capabilities rather than a specific desktop product. A runtime is supported
only after it passes the pinned-image, port-forwarding, health-check, topic,
repeat-start, and teardown tests.

- [**OrbStack**](https://docs.orbstack.dev/docker/) passed the broker, pinned
  image, health-check, topic-creation, repeat-start, teardown, and host-port
  tests on this host. It supplies a Docker engine, Docker CLI, Compose, port
  forwarding, and Apple Silicon x86 emulation. Both headless traffic directions
  also passed. Final demo support still requires interactive Shapes Demo in a
  fresh checkout.
- [**Colima**](https://github.com/abiosoft/colima) is the CLI-first candidate.
  Start it with the Docker runtime and install the Docker client and Compose
  plugin; the containerd runtime does not satisfy the current scripts.
- [**Podman Desktop**](https://podman-desktop.io/docs/migrating-from-docker/managing-docker-compatibility)
  is a compatibility candidate. Enable its Docker socket compatibility and
  Compose support before running the scripts. Podman behavior must be tested
  against the Confluent images before it is documented as supported.
- [**Rancher Desktop**](https://docs.rancherdesktop.io/ui/preferences/container-engine/general/)
  is a compatibility candidate only when its container engine is `moby`
  (`dockerd`). Its `containerd`/`nerdctl` mode does not expose the Docker API
  required by the current scripts.

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
- RTI-recommended System V shared-memory limits on macOS

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
- The selected Docker-compatible engine can pull the pinned image.
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

Implement macOS interactive launch through Terminal.app log views and Ubuntu
interactive launch through GNOME Terminal while the native child processes
remain directly owned by the startup shell. Keep process ownership independent
of terminal window titles.

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
required. Keep GNOME Terminal installed for the interactive presenter windows;
it is part of the standard Ubuntu Desktop baseline.

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

The tested Apple Silicon workflow is published separately in
[MACOS.md](MACOS.md). The Ubuntu implementation workflow is published in
[UBUNTU.md](UBUNTU.md). After each remaining target passes clean-room testing:

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
| macOS defaults cannot allocate Connext shared-memory resources | Fail prerequisite validation with detected values and link to RTI's administrator procedure |
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
