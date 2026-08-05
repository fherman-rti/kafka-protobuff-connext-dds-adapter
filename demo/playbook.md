# Kafka + Protobuf Shapes Demo — Playbook

Step-by-step instructions for running the customer-facing demo: RTI Routing
Service bridging DDS Shapes traffic to/from Kafka, with Protocol Buffers
serialization in between.

All commands below are PowerShell and use the **full absolute path** to each
script, so they can be run from any directory/terminal — you do not need to
`cd` anywhere first. The workspace root referenced throughout is:

```
C:\Users\fherman\Documents\kafka-proto-buff-adapter
```

Prerequisites (one-time, already completed in this workspace):
- RTI Connext DDS Professional 7.7.0 installed with a valid license.
- The `rticonnextdds-gateway` repo built and installed (see the root
  [README.md](../README.md) for the CMake configure/build/install steps).
- Docker Desktop installed.

---

## 1. Start Docker Desktop

Kafka runs in a container, so Docker Desktop's engine must be running before
anything else.

1. Launch Docker Desktop and wait for it to report "Engine running".
2. Confirm from a terminal:
   ```powershell
   docker info --format "{{.ServerVersion}}"
   ```
   This should print a version number (e.g. `26.1.1`), not a connection error.

## 2. Validate prerequisites

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\fherman\Documents\kafka-proto-buff-adapter\demo\scripts\Test-Prerequisites.ps1"
```

This checks the Connext install, license, Gateway build artifacts, Docker
CLI/daemon/Compose, and that ports `9092` (Kafka) and `9021` (Control Center)
are free. Fix anything reported as `[FAIL]` before continuing. A `[WARN]` on
"Kafka broker reachable" is expected at this point — the broker isn't started
yet.

## 3. Start Kafka (with Control Center)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\fherman\Documents\kafka-proto-buff-adapter\demo\scripts\Start-Kafka.ps1" -WithControlCenter
```

This starts the single-broker KRaft-mode Kafka container plus Confluent
Control Center, waits for the broker to report healthy, and creates the
`Square` and `Circle` topics used by the demo. On success you'll see:

```
Kafka broker ready at localhost:9092 with topics: Square, Circle
```

(Omit `-WithControlCenter` if you only need the broker — Control Center adds
noticeable startup time and isn't required for the demo to function.)

### Checking the broker container's status/resource usage

The broker runs inside a Linux container under Docker Desktop's WSL2 backend,
so it won't show up as its own process in Windows Task Manager (only
`Vmmem`/`Vmmemwsl` and Docker's own management processes will). To inspect it
directly, use Docker's tools instead:

```powershell
docker stats kafka-shapes-protobuf-broker
```
Live CPU/memory/network usage for just the broker container (Ctrl+C to exit).

```powershell
docker top kafka-shapes-protobuf-broker
```
Lists the actual processes (the Kafka JVM) running inside the container.

## 4. Show the customer the Kafka topics via Control Center

1. Open a browser to **http://localhost:9021**.
2. Select the cluster (named after its `CLUSTER_ID`, e.g.
   `ug25vkvheEyeQ8hF7F5xZA`).
3. Click **Topics** in the left nav.
4. Point out `Square` and `Circle` in the list — these are the two
   demo-created topics. (The **Cluster overview** page shows a much larger
   "Topics" count; that includes Control Center's and Kafka's own internal
   bookkeeping topics like `_confluent-controlcenter-*`, `__consumer_offsets`,
   etc. The filtered **Topics** page is the clean view to show a customer.)

This step is optional narrative — it's a good visual to open once at the
start of a live demo, but the decoded Kafka subscriber window (step 6) is
the more compelling proof once messages are flowing.

## 5. Launch the demo stack

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\fherman\Documents\kafka-proto-buff-adapter\demo\scripts\Start-Demo.ps1"
```

This opens four windows and records their process IDs to
`demo\logs\demo-state.json`:

| Window                                   | Purpose                                                              |
|-------------------------------------------|-----------------------------------------------------------------------|
| **Routing Service**                       | Loads the Kafka adapter + Protobuf transformation plugins            |
| **Kafka Subscriber (Square)**             | Decodes and prints Protobuf messages arriving on the `Square` topic  |
| **Kafka Publisher (Circle) — press Enter**| Paused; will publish `GREEN` circles to Kafka once you press Enter   |
| **Shapes Demo**                           | The RTI Shapes Demo GUI                                             |

Check the **Routing Service** window for a clean startup — no errors loading
the Kafka adapter or Protobuf transformation plugins.

## 6. Run the live sequence in Shapes Demo

1. In **Shapes Demo**: **Subscribe → Circle**.
   - Leave the **Kafka Publisher (Circle)** window paused for now — nothing
     is publishing circles yet, so nothing appears.
2. In **Shapes Demo**: **Publish → Square**, color **BLUE**, click OK.
   - Watch the **Kafka Subscriber (Square)** window: it should start printing
     decoded samples, e.g. `color=BLUE, x=<n>, y=<n>, shapesize=<n>`. This
     proves the DDS → Protobuf serialize → Kafka leg.
3. Switch to the **Kafka Publisher (Circle)** window and press **Enter**.
   - It starts publishing `GREEN` circles to the Kafka `Circle` topic every
     ~1 second.
   - Watch **Shapes Demo**: green circles should appear on the canvas. This
     proves the Kafka → Protobuf deserialize → DDS leg.

At this point both directions of the bridge are demonstrated live.

### Known benign log line

The Routing Service window may log:

```
ERROR DDS_DynamicData2_get_string: Output buffer too small for member (name = "color", id = 1). Provided size (N), requires size (N+1).
```

This has been fixed as of the local patch to
`rticonnextdds-gateway/common/protobuf2dds/srcCxx/DdsToProtobuf.cpp` (see
repo memory notes) — it should no longer appear. If it does, confirm
`rtiprotobuftransf.dll` was rebuilt/reinstalled and Routing Service was
restarted after the patch (the DLL is only loaded at process startup).

## 7. Stop the demo

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\fherman\Documents\kafka-proto-buff-adapter\demo\scripts\Stop-Demo.ps1"
```

Stops only the processes recorded in `demo\logs\demo-state.json` (Routing
Service, subscriber, publisher, Shapes Demo) and tears down the Docker
Compose project (broker + Control Center, if running).

Use `-SkipKafka` to leave the Kafka broker running (e.g. if you plan to
restart the demo again shortly):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\fherman\Documents\kafka-proto-buff-adapter\demo\scripts\Stop-Demo.ps1" -SkipKafka
```

## 8. Collect logs (troubleshooting only)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\fherman\Documents\kafka-proto-buff-adapter\demo\scripts\Collect-Logs.ps1"
```

Zips Routing Service/publisher/subscriber logs, the demo state file, the
Kafka broker container log, and the resolved Routing Service config into
`demo\logs\collected\<timestamp>.zip`.

---

## Troubleshooting quick reference

| Symptom                                                       | Cause / Fix                                                                                     |
|-----------------------------------------------------------------|---------------------------------------------------------------------------------------------------|
| `Test-Prerequisites.ps1` fails "Docker daemon reachable"        | Start Docker Desktop and wait for "Engine running" before retrying.                              |
| Kafka container exits immediately (`docker ps -a` shows `Exited (1)`) | Check `docker logs kafka-shapes-protobuf-broker` — a common cause is an invalid `CLUSTER_ID` in `demo\docker\docker-compose.yml` (must be a base64-encoded 16-byte UUID, not an arbitrary string). |
| `Start-Kafka.ps1` health-wait loop seems to hang                | The container may have already exited. Cross-check with `docker ps -a` / `docker logs` rather than waiting out the full timeout. |
| Port 9092 or 9021 already in use                                | Another Kafka/Control Center instance is running — stop it or change the port mapping in `docker-compose.yml`. |
| Benign `DDS_DynamicData2_get_string` ERROR in Routing Service    | See "Known benign log line" above — fixed by the local `DdsToProtobuf.cpp` patch; restart Routing Service if you still see it after patching. |
