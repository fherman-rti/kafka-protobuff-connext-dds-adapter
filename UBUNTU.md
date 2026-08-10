# Ubuntu 22.04 x64 Clean-room Installation and Demo

This is the installation and demonstration path for an Ubuntu 22.04 Desktop
x64 system. It builds the Gateway Kafka adapter, Protobuf transformation, and
example applications, then runs both demo directions:

```text
DDS Square -> Protobuf -> Kafka Square
Kafka Circle -> Protobuf -> DDS Circle
```

The workflow uses Bash, Docker Engine with the Compose v2 plugin, and GNOME
Terminal. PowerShell, Ninja, Docker Desktop, and a separate `protoc`
installation are not required.

> **Validation status:** This workflow passed a complete Ubuntu 22.04 x64
> VirtualBox clean-room installation and end-to-end rehearsal on 2026-08-10.
> Both traffic directions worked, and shutdown closed all four demo windows and
> removed the broker and Compose network.

## 1. Prepare the Ubuntu host

The validation baseline is Ubuntu 22.04 Desktop x64 in VirtualBox with:

- 4 virtual CPUs
- 8 GB RAM
- 50 GB dynamically allocated disk
- 128 MB video memory and 3D acceleration
- Guest Additions
- NAT networking

Clone and build on the VM's native Linux filesystem, not a VirtualBox shared
folder. Run Kafka, Routing Service, the example applications, and Shapes Demo
inside the VM for the first end-to-end test.

Install the native build and desktop packages:

```bash
sudo apt update
sudo apt install -y build-essential cmake git python3 netcat-openbsd \
  gnome-terminal
```

Install RTI Connext DDS Professional 7.7.0 for Linux x64, including Routing
Service and Shapes Demo. Keep the installer's default location:
`$HOME/rti_connext_dds-7.7.0`. Place a valid `rti_license.dat` in that
directory.

Install Docker Engine from Docker's official Ubuntu repository by following
[Install Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/).
Install these Docker packages from that repository:

```text
docker-ce
docker-ce-cli
containerd.io
docker-buildx-plugin
docker-compose-plugin
```

Add the current user to the `docker` group, then log out of the Ubuntu desktop
and log back in so the new group membership takes effect:

```bash
sudo usermod -aG docker "$USER"
```

Do not run the repository scripts with `sudo`. Verify the host after logging
back in:

```bash
uname -m
gcc --version
cmake --version
gnome-terminal --version
docker version
docker compose version
docker info --format '{{.ServerVersion}}'
test -d "$HOME/rti_connext_dds-7.7.0"
test -f "$HOME/rti_connext_dds-7.7.0/rti_license.dat"
```

`uname -m` must print `x86_64`. The Docker commands and both `test` commands
must succeed without `sudo`.

The scripts automatically select Connext at the default home-directory
location. `/opt/rti_connext_dds-7.7.0` and explicit `NDDSHOME` or
`CONNEXTDDS_DIR` values remain supported for non-default installations.

## 2. Clone the repository

In GNOME Terminal, change to the parent directory in which the repository
should be installed. `git clone` creates the repository directory.

```bash
git clone https://github.com/fherman-rti/kafka-protobuff-connext-dds-adapter.git
cd kafka-protobuff-connext-dds-adapter
source ~/rti_connext_dds-7.7.0/resource/scripts/rtisetenv_x64Linux4gcc8.5.0.bash
```

The `source` command must run in every new Terminal used for the demo. From
this point forward, run repository commands from this directory. Confirm the
included Gateway source and Ubuntu launcher are present:

```bash
test -f rticonnextdds-gateway/CMakeLists.txt
test -f demo/scripts/Start-Demo.sh
```

## 3. Build the Gateway components

The build script configures a Release x64 build with GCC and Unix Makefiles. It
installs the Kafka adapter, Protobuf transformation, descriptor, publisher, and
subscriber beneath `rticonnextdds-gateway/install`.

```bash
./demo/scripts/Build-Gateway.sh
```

The build is complete when it prints `Gateway build and installation
completed`. The script uses `file` and `ldd` to reject non-x64 artifacts and
unresolved dependencies. Do not continue after an error.

<strong><ins>SKIP to section 4 if the previous command succeeds.</ins></strong>

If Connext is installed elsewhere or architecture discovery is ambiguous,
inspect the available targets and provide both values explicitly:

```bash
find /path/to/rti_connext_dds-7.7.0/lib \
  -maxdepth 1 -type d -name 'x64Linux*'

./demo/scripts/Build-Gateway.sh \
  --connext-dir /path/to/rti_connext_dds-7.7.0 \
  --connext-arch VERIFIED_X64_LINUX_TARGET
```

Use the architecture name actually installed on the system; do not copy a
name from another Connext installation.

## 4. Validate the installation

Make sure Docker Engine is running:

```bash
sudo systemctl enable --now docker
docker info --format '{{.ServerVersion}}'
```

Only the service-management command uses `sudo`; the Docker client command
must work as the regular user. Then run the repository prerequisite check:

```bash
./demo/scripts/Test-Prerequisites.sh
```

Continue only when it ends with `Prerequisite check PASSED.` A warning that
Kafka is not reachable is expected because the broker starts next. In a GNOME
desktop session, the check also verifies GNOME Terminal for the interactive
viewer windows.

<strong><ins>SKIP to section 5 if the previous command succeeds.</ins></strong>

For a non-standard Connext installation, pass the same `--connext-dir` and
`--connext-arch` values used for the build.

## 5. Start Kafka

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

Open <http://localhost:9021> in the VM browser to inspect topic activity.
Control Center does not decode this demo's raw Protobuf payloads; use the native
subscriber window for decoded values.

If port `9021` is unavailable or Control Center is not needed, start only the
broker:

```bash
./demo/scripts/Start-Kafka.sh
```

## 6. Run the interactive demonstration

Run this command from a GNOME desktop session, using an otherwise unused DDS
domain:

```bash
./demo/scripts/Start-Demo.sh --domain-id 101
```

The launcher creates Shapes Demo plus GNOME Terminal windows for Routing
Service, the decoded Kafka `Square` subscriber, and the staged Kafka `Circle`
publisher. The publisher window waits at this prompt:

```text
Press Enter to start publishing GREEN circles to Kafka topic Circle:
```

Leave the publisher waiting while performing the first two actions:

1. In Shapes Demo, select **Subscribe -> Circle**.
2. In Shapes Demo, select **Publish -> Square**, choose **BLUE**, and confirm.
   The **Kafka Subscriber (Square)** window should print decoded BLUE samples
   with `color`, `x`, `y`, and `shapesize` fields.
3. Switch to the **Kafka Publisher (Circle)** window and press **Enter**.
4. Watch Shapes Demo display moving GREEN circles.

The first path proves DDS-to-Protobuf-to-Kafka traffic. The second proves
Kafka-to-Protobuf-to-DDS traffic. Process output is also written beneath
`demo/logs`.

### Optional headless smoke run

For SSH or process-only startup, omit Shapes Demo and GNOME Terminal windows:

```bash
./demo/scripts/Start-Demo.sh \
  --domain-id 101 \
  --headless \
  --start-publisher-immediately
```

Because this does not start Shapes Demo, it is a startup smoke test rather than
proof of both end-to-end traffic directions.

## 7. Stop the demonstration

From the repository root, run:

```bash
./demo/scripts/Stop-Demo.sh
```

The script stops only processes whose PID, start marker, and executable still
match `demo/logs/demo-state.json`. GNOME Terminal log viewers exit when their
corresponding application processes stop. The script also removes the Kafka
and Control Center containers and the Compose network.

To keep Kafka running for another demo launch:

```bash
./demo/scripts/Stop-Demo.sh --skip-kafka
```

## 8. Collect troubleshooting logs

When a run fails, collect its support bundle before stopping Kafka:

```bash
./demo/scripts/Collect-Logs.sh
```

The script creates a timestamped directory and ZIP archive beneath
`demo/logs/collected`. The bundle includes application logs, Docker diagnostics,
the Routing Service configuration, platform details, and `ldd` output. Then
run `Stop-Demo.sh`.

## 9. VirtualBox networking after local validation

Keep all components inside the VM until both traffic directions pass. After
that local test:

- Add NAT forwarding only when the host must access ports `9021` or `9092`.
- Use bridged networking only when DDS participants must cross the VM boundary.
- Test DDS discovery explicitly across the boundary.
- Configure DDS discovery peers if VirtualBox multicast is unreliable.

## Troubleshooting

| Symptom | Action |
| --- | --- |
| `uname -m` does not print `x86_64` | Use an x64 Ubuntu VM; the scripts reject other Linux architectures. |
| Docker reports permission denied | Confirm `id -nG` includes `docker`, then log out and back in. Do not run demo scripts with `sudo`. |
| Docker Engine is unreachable | Run `sudo systemctl enable --now docker`, then verify `docker info` as the regular user. |
| `docker compose` is not found | Install Docker's `docker-compose-plugin`; legacy `docker-compose` is not supported. |
| Interactive startup reports no desktop | Run from GNOME Terminal in the VM desktop, or use `--headless` over SSH. |
| `gnome-terminal` is missing | Install the `gnome-terminal` package, then rerun the prerequisite check. |
| Connext selection is ambiguous | Pass verified `--connext-dir` and `--connext-arch` values consistently to the build, prerequisite, and demo scripts. |
| `ldd` reports a missing library | Confirm the selected Connext architecture matches Linux x64 and rebuild from a clean `b-linux` directory. |
| Port `9092` or `9021` is occupied | Stop the other service or previous Compose project. Use broker-only startup when only `9021` is unavailable. |
| `demo-state.json` already exists | Run `./demo/scripts/Stop-Demo.sh`; it validates process ownership before stopping anything. |

For implementation details and the remaining cross-platform work, see
[PORTING.md](PORTING.md). The tested Apple Silicon workflow is in
[MACOS.md](MACOS.md), and the Windows workflow remains in
[README.md](README.md) and [demo/playbook.md](demo/playbook.md).
