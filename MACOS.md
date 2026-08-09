# macOS Apple Silicon Clean-room Installation and Demo

This is the tested installation and demonstration path for a clean Apple
Silicon Mac. It builds the Gateway Kafka adapter, Protobuf transformation, and
example applications as native ARM64 binaries, then runs both demo directions:

```text
DDS Square -> Protobuf -> Kafka Square
Kafka Circle -> Protobuf -> DDS Circle
```

The workflow uses the system `/bin/bash`. PowerShell, Ninja, Rosetta, and a
separate `protoc` installation are not required. Intel Macs are not supported.

The clean-room rehearsal recorded in [PORTING.md](PORTING.md) passed on macOS
26.3 with RTI Connext DDS Professional 7.7.0 and OrbStack 2.2.3. The scripts
require an Apple Silicon host and a Docker-compatible CLI/engine with Compose
v2; macOS 26.3 and that exact OrbStack version are the validated baseline, not
declared minimum versions.

## 1. Install the host prerequisites

Install these products before cloning the repository. The numbered workflow
below assumes the standard Connext installation at
`/Applications/rti_connext_dds-7.7.0`; its commands are ready to copy and paste
without editing paths or arguments.

- RTI Connext DDS Professional 7.7.0 for Apple Silicon, installed at
  `/Applications/rti_connext_dds-7.7.0` and including Routing Service and
  Shapes Demo.
- A valid Connext license. Place `rti_license.dat` in the Connext installation
  directory.
- Apple's Command Line Tools, which provide Apple Clang, Make, and Git.
- CMake 3.10 or newer, with `cmake` available on `PATH`.
- [OrbStack](https://docs.orbstack.dev/quick-start), the recommended and
  validated container runtime for this workflow. It provides the Docker
  engine, `docker` CLI, and `docker compose` v2 required by the demo.

Open a normal ARM64 Terminal window, not a shell running through Rosetta. Use
this command if the Apple Command Line Tools are not installed:

```bash
xcode-select --install
```

After the installers finish, open a new Terminal window and verify the native
toolchain:

```bash
uname -m
arch
git --version
cmake --version
clang --version
make --version
orb version
test -d /Applications/rti_connext_dds-7.7.0
test -f /Applications/rti_connext_dds-7.7.0/rti_license.dat
```

Both `uname -m` and `arch` must print `arm64`. The two `test` commands must
exit without printing an error.

The scripts automatically select Connext when it is installed at
`/Applications/rti_connext_dds-7.7.0`. A different installation is supported;
run each script with `--help` and pass its actual path with `--connext-dir`. If
more than one matching ARM64 target is installed, also pass the verified target
name with `--connext-arch`. Those non-standard arguments are not part of the
copy-and-paste workflow below.

## 2. Configure macOS shared memory and reboot

Connext 7.7 uses shared-memory resources for the demo participants, Distributed
Logger, and Monitoring Library 2.0. The default macOS limits can cause startup
to fail with an observability participant or `No index available for
participant` error.

Follow RTI's
[macOS shared-memory instructions](https://community.rti.com/kb/osx510) to
install its Catalina-and-later `memory.plist` launch daemon, then reboot. This
is a one-time administrator-owned host change; the repository scripts do not
modify kernel settings.

After the reboot, verify the four limits:

```bash
sysctl kern.sysv.shmmax kern.sysv.shmmni kern.sysv.shmseg kern.sysv.shmall
```

They must be at least:

| Setting | Minimum |
| --- | ---: |
| `kern.sysv.shmmax` | `419430400` |
| `kern.sysv.shmmni` | `128` |
| `kern.sysv.shmseg` | `1024` |
| `kern.sysv.shmall` | `262144` |

Do not continue if a value is lower. In particular, a live `sysctl` change may
not update `shmmni` while System Integrity Protection is enabled; the reboot is
required.

## 3. Clone the repository

In Terminal, change to the parent directory in which the repository should be
installed. Do not create the repository directory yourself; `git clone`
creates it.

```bash
git clone https://github.com/fherman-rti/kafka-protobuff-connext-dds-adapter.git
cd kafka-protobuff-connext-dds-adapter
```

From this point forward, run every repository command from this directory. It
is the "repository root." Confirm the included Gateway source and macOS script
are present:

```bash
test -f rticonnextdds-gateway/CMakeLists.txt
test -f demo/scripts/Start-Demo.sh
```

Both commands must exit without printing an error.

## 4. Build the Gateway components

The build script configures a native ARM64 Release build with Unix Makefiles
and installs the Kafka adapter, Protobuf transformation, descriptor, publisher,
and subscriber beneath `rticonnextdds-gateway/install`.

```bash
./demo/scripts/Build-Gateway.sh
```

The build is complete when it prints `Gateway build and installation
completed`. Do not continue after an error.

**SKIP to section 5** if the previous command succeeds.

Only when architecture discovery reports more than one target in the standard
installation, inspect the installed directories and pass the validated ARM64
name explicitly:

```bash
find /Applications/rti_connext_dds-7.7.0/lib \
  -maxdepth 1 -type d -name 'arm64Darwin*'

./demo/scripts/Build-Gateway.sh \
  --connext-dir /Applications/rti_connext_dds-7.7.0 \
  --connext-arch arm64Darwin23clang16.0
```

The architecture name above is the validated Connext 7.7.0 target. Use the
name actually present in the selected installation rather than assuming it is
identical.

## 5. Start the container runtime and validate the installation

Start OrbStack and wait for its engine to become ready:

```bash
orb start
```

The runtime must expose its CLI and Compose plugin normally on `PATH`:

```bash
docker version
docker compose version
docker info --format '{{.ServerVersion}}'
```

All three commands must succeed. Then run the complete repository check:

```bash
./demo/scripts/Test-Prerequisites.sh
```

Continue only when it ends with `Prerequisite check PASSED.` A warning that
Kafka is not reachable is expected because the broker starts in the next step.

**SKIP to section 6** if the previous command succeeds.

If the prerequisite check reports ambiguous architecture discovery in the
standard installation, use the same explicit selection as the build:

```bash
./demo/scripts/Test-Prerequisites.sh \
  --connext-dir /Applications/rti_connext_dds-7.7.0 \
  --connext-arch arm64Darwin23clang16.0
```

## 6. Start Kafka

Start the pinned single-broker Kafka environment with Control Center and create
the `Square` and `Circle` topics:

```bash
./demo/scripts/Start-Kafka.sh --with-control-center
```

The environment is ready when the script prints:

```text
Kafka broker ready at localhost:9092 with topics: Square, Circle
Control Center available at http://localhost:9021
```

Open <http://localhost:9021>, select the cluster, and open
**Topics**. Control Center can show topic activity, but it does not decode this
demo's raw Protobuf payloads; use the native subscriber window for decoded
values.

If port `9021` is unavailable and the browser view is not required, start only
the broker instead:

```bash
./demo/scripts/Start-Kafka.sh
```

## 7. Run the interactive demonstration

Use an otherwise unused DDS domain. Domain 101 was used for the clean-room
rehearsal:

```bash
./demo/scripts/Start-Demo.sh --domain-id 101
```

The launcher creates all four demonstration windows at startup: Shapes Demo
plus Terminal viewers for Routing Service, the decoded Kafka `Square`
subscriber, and the staged Kafka `Circle` publisher. It then pauses in the
original Terminal at this prompt:

```text
Press Enter here when ready to publish GREEN circles to Kafka topic Circle:
```

Leave that prompt waiting while performing the first two actions:

1. In Shapes Demo, select **Subscribe -> Circle**.
2. In Shapes Demo, select **Publish -> Square**, choose **BLUE**, and confirm.
   The **Kafka Subscriber (Square)** log should begin printing decoded BLUE
   samples with `color`, `x`, `y`, and `shapesize` fields. This proves the
   DDS-to-Protobuf-to-Kafka path.
3. Return to the original Terminal and press **Enter**. The launcher starts the
   Kafka `Circle` publisher, and its already-open viewer begins showing output.
4. Watch Shapes Demo display moving GREEN circles. This proves the
   Kafka-to-Protobuf-to-DDS path.

Routing Service, Shapes Demo, the publisher, and the subscriber continue to run
after the launcher returns. Their output is also written under `demo/logs`.

### Optional headless smoke run

For an SSH session or a process-only startup check, omit Shapes Demo and the
Terminal log viewers:

```bash
./demo/scripts/Start-Demo.sh \
  --domain-id 101 \
  --headless \
  --start-publisher-immediately
```

This starts Routing Service and both Kafka example processes, with output under
`demo/logs`. Because it does not start Shapes Demo, it is a startup smoke test,
not proof of both end-to-end traffic directions. Use `Stop-Demo.sh` when the
check is complete.

## 8. Stop the demonstration

From the repository root, run:

```bash
./demo/scripts/Stop-Demo.sh
```

The script stops only processes whose PID, start marker, and executable still
match `demo/logs/demo-state.json`. It also closes inactive Terminal log windows
created by the launcher and removes the Kafka/Control Center containers and
Compose network.

To keep Kafka running for another demo launch:

```bash
./demo/scripts/Stop-Demo.sh --skip-kafka
```

## 9. Collect troubleshooting logs

When a run fails, collect its support bundle before stopping Kafka so the
broker log and live Compose status are available:

```bash
./demo/scripts/Collect-Logs.sh
```

The script writes a timestamped directory and ZIP archive beneath
`demo/logs/collected` containing application logs, Docker diagnostics, the
resolved Routing Service configuration, platform details, and native binary
dependency information. Then run `Stop-Demo.sh`.

## Troubleshooting

| Symptom | Action |
| --- | --- |
| The script rejects `x86_64` or reports Rosetta | Open a native ARM64 Terminal and confirm both `uname -m` and `arch` print `arm64`. |
| Shared-memory prerequisite fails | Follow RTI's linked procedure, reboot, and confirm all four `sysctl` values meet the table above. Do not disable Connext observability as a workaround. |
| `docker` or `docker compose` is not found | Enable the selected runtime's normal Docker CLI integration, open a new Terminal, and rerun the three Docker checks. Repository scripts do not install or patch the runtime. |
| Docker engine is unreachable | Run `orb start` and wait until `docker info` succeeds. |
| Port `9092` or `9021` is occupied | Stop the other service or previous Compose project before starting this demo. If only `9021` is unavailable, use the documented broker-only startup. |
| Connext selection is ambiguous | Pass the verified `--connext-dir` and `--connext-arch` values consistently to the build, prerequisite, and demo scripts. |
| `demo-state.json` already exists | Run `./demo/scripts/Stop-Demo.sh`; it validates process ownership before stopping anything. |
| Routing Service reports a loaned octet-sequence buffer error during shutdown | This known adapter cleanup diagnostic occurs while the Kafka reader is being disabled; it did not prevent startup or message processing in validation. Capture logs if it occurs at any other time. |

For the implementation history, platform findings, and Ubuntu work, see
[PORTING.md](PORTING.md). The Windows workflow remains in [README.md](README.md)
and [demo/playbook.md](demo/playbook.md).
