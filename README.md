# RTI Routing Service Kafka/Protobuf Shapes Demonstration

This repository is intended to package a customer-ready demonstration of the
RTI Routing Service Kafka adapter with RTI Shapes Demo and Protocol Buffers.
The upstream implementation is in the
[RTI Connext Gateway repository](https://github.com/rticommunity/rticonnextdds-gateway),
under its
[Kafka Shapes Protobuf example](https://github.com/rticommunity/rticonnextdds-gateway/tree/master/examples/kafka/kafka-shapes-protobuf).

## Objective

Demonstrate both integration directions:

```text
DDS -> Kafka
RTI Shapes Demo publishes BLUE squares on DDS topic Square
    -> RTI Routing Service
    -> ShapeType is serialized as Protobuf
    -> Kafka topic Square
    -> Kafka subscriber prints the decoded fields

Kafka -> DDS
Kafka publisher produces GREEN shapes on Kafka topic Circle
    -> RTI Routing Service
    -> Protobuf is deserialized as DDS ShapeType
    -> DDS topic Circle
    -> RTI Shapes Demo displays green circles
```

Using different shape topics for the two directions permits both routes to run
concurrently without creating a DDS/Kafka feedback loop.

## Upstream baseline

Use the upstream `master` branch pinned to commit
[`a9e68fb`](https://github.com/rticommunity/rticonnextdds-gateway/commit/a9e68fbdf5a6b32dc766eb1f38b41ba9fdbe4d0d).

Do not use an unpinned branch for a customer demonstration. Although the
upstream README identifies `develop` as the active branch for Connext 7.7, the
remote `develop` branch is currently based on an older 2021 commit and does not
contain the current Kafka/Protobuf example. There are also versioning
inconsistencies: the latest commit says that the repository was updated for
Connext 7.7, while the CMake project and
[published Gateway documentation](https://community.rti.com/static/documentation/gateway/current/index.html)
still identify themselves as version 7.3.0. Compatibility with the selected
Connext installation must therefore be verified during rehearsal.

Clone the complete source tree and its submodules:

```powershell
git clone --recurse-submodules https://github.com/rticommunity/rticonnextdds-gateway.git
Set-Location rticonnextdds-gateway
git checkout a9e68fbdf5a6b32dc766eb1f38b41ba9fdbe4d0d
git submodule update --init --recursive
```

Then apply the local fix kept in this repo's [patches/](patches/README.md)
directory (see that file for what it fixes) before building:

```powershell
git apply "..\patches\DdsToProtobuf.cpp.patch"
```

## Important upstream caveats

The upstream example is a useful starting point, but it should not be presented
unchanged:

- The checked-in
  [Windows launcher](https://github.com/rticommunity/rticonnextdds-gateway/blob/master/examples/kafka/kafka-shapes-protobuf/scripts/windows_run_all.bat)
  is an erroneous MQTT/Mosquitto copy and does not launch the Kafka example.
- The Unix `tmux` launcher runs Kafka commands but retains stale MQTT names and
  creates an unused MQTT window.
- The supplied
  [Routing Service XML](https://github.com/rticommunity/rticonnextdds-gateway/blob/master/examples/kafka/kafka-shapes-protobuf/shapesdemo_kafka_protobuf.xml)
  routes DDS topic `Square` to Kafka topic `Square` and the same Kafka topic
  back to DDS. The adapter has no obvious origin filtering, so this layout has
  a message-feedback risk.
- Kafka messages contain raw Protobuf payloads. They do not use the Confluent
  Schema Registry wire format. The example's native Kafka subscriber should be
  used to show decoded values; Control Center is useful for topic activity and
  counts but should not be expected to decode the payload automatically.
- The example is part of an experimental, source-distributed Gateway rather
  than an installed Routing Service feature. Build provenance and exact
  versions should be disclosed when presenting it.

## Prerequisites

- RTI Connext DDS Professional 7.7.0, including:
  - RTI Routing Service
  - RTI Shapes Demo
  - A valid license
- The Connext architecture matching the compiler; on the current Windows host,
  this is `x64Win64VS2017`
- Git with submodule support
- CMake 3.10 or newer
- A supported C/C++ build toolchain
- Docker Engine and Docker Compose for the Kafka broker
- Ports `9092` for Kafka and, if selected, `9021` for Confluent Control Center
- PowerShell for the planned Windows launch automation

A separate `protoc` installation is not required when the bundled Protobuf
build is enabled.

## Build plan

Use a Release build so that the plugins match the normal Routing Service
executable. Debug plugins require the debug Routing Service executable.

Build only the Kafka adapter, Protobuf transformation, and their example:

```powershell
cmake -S . -B build `
  -G "Visual Studio 17 2022" `
  -A x64 `
  -DCONNEXTDDS_DIR="C:\Program Files\rti_connext_dds-7.7.0" `
  -DCONNEXTDDS_ARCH=x64Win64VS2017 `
  -DCMAKE_INSTALL_PREFIX=install `
  -DRTIGATEWAY_ENABLE_ALL=OFF `
  -DRTIGATEWAY_ENABLE_KAFKA=ON `
  -DRTIGATEWAY_ENABLE_TSFM_PROTOBUF=ON `
  -DRTIGATEWAY_ENABLE_EXAMPLES=ON `
  -DRTIGATEWAY_ENABLE_PROTOBUF_BUILD=ON `
  -DRTIGATEWAY_ENABLE_TESTS=OFF

cmake --build build --config Release --target install
```

Confirm that the installation contains at least:

```text
install/lib/rtikafkaadapter.dll
install/lib/rtiprotobuftransf.dll
install/examples/kafka/kafka-shapes-protobuf/shape_type.pbdesc
install/examples/kafka/kafka-shapes-protobuf/bin/shapes_kafka_publisher.exe
install/examples/kafka/kafka-shapes-protobuf/bin/shapes_kafka_subscriber.exe
```

The demonstration shell must include the Gateway `install/lib` directory and
the matching Connext `lib/x64Win64VS2017` directory in `PATH` before starting
Routing Service or either example application.

## Kafka environment plan

Use a single, version-pinned Kafka broker in KRaft mode. A minimal Compose file
is preferred over the full Confluent `cp-all-in-one` environment because it
starts faster and has fewer failure points. Control Center can be added when a
browser view of topic traffic is useful.

Create two single-partition topics:

```text
Square  - DDS-to-Kafka route
Circle  - Kafka-to-DDS route
```

For a local demonstration, each topic can use replication factor one. Scripts
must wait for broker readiness and verify both topics before launching Routing
Service.

## Routing Service configuration plan

Create a demonstration-specific copy of the upstream XML with these routes:

| Route | Input | Transformation | Output |
| --- | --- | --- | --- |
| DDS to Kafka | DDS `Square`, `ShapeType` | Serialize using `shape_type.pbdesc` | Kafka `Square` |
| Kafka to DDS | Kafka `Circle`, raw Protobuf | Deserialize using `shape_type.pbdesc` | DDS `Circle`, `ShapeType` |

Additional configuration requirements:

- Use DDS domain `0` unless the customer environment requires another domain.
- Set `bootstrap.servers` explicitly.
- Give the Kafka input an explicit, demonstration-specific `group.id`.
- Retain `auto.offset.reset=latest` for a clean live demonstration.
- Start Routing Service before producing Kafka `Circle` samples because the
  consumer starts at the latest offset.
- Make the broker address and DDS domain easy to override.
- Keep the descriptor file adjacent to the XML or use a resolved absolute path.
- Add clear Routing Service logging for plugin load, Kafka connectivity, and
  transformation failures.

## Automation deliverables

Replace the upstream launch scripts with PowerShell automation appropriate for
the customer demonstration:

- `Test-Prerequisites.ps1`: validate Connext, license, build artifacts, Docker,
  ports, and broker connectivity.
- `Start-Kafka.ps1`: start the broker, wait for readiness, and create `Square`
  and `Circle`.
- `Start-Demo.ps1`: configure library paths and start Routing Service, the
  decoded Kafka subscriber, the Kafka publisher, and Shapes Demo in readable
  windows.
- `Stop-Demo.ps1`: stop only the processes and containers belonging to this
  demonstration.
- `Collect-Logs.ps1`: gather Routing Service, Kafka, publisher, and subscriber
  logs for troubleshooting.

Startup should fail early with an actionable message if a prerequisite or
expected artifact is missing.

## Customer demonstration sequence

1. Show the two data paths and explain that Routing Service uses three plugins:
   the built-in DDS adapter, the Kafka adapter, and the Protobuf
   transformation.
2. Start Kafka and confirm that the `Square` and `Circle` topics are ready.
3. Start the decoded Kafka subscriber on topic `Square`.
4. Start Routing Service and point out successful Kafka adapter, Protobuf
   transformation, and descriptor initialization.
5. Start Shapes Demo.
6. In Shapes Demo, subscribe to `Circle` with default parameters.
7. In Shapes Demo, publish a BLUE `Square` at a one-second interval.
8. Show BLUE square samples arriving in the Kafka subscriber with decoded
   `color`, `x`, `y`, and `shapesize` values.
9. Start the Kafka publisher with color GREEN on topic `Circle`.
10. Show green circles appearing in Shapes Demo.
11. Briefly show `shape_type.proto` and the two XML transformations to connect
    the visible behavior to the configuration.

## Acceptance criteria

The demonstration is ready for a customer when all of the following are true:

- DDS-to-Kafka and Kafka-to-DDS operate concurrently for at least ten minutes.
- Approximately one input sample produces one output sample, with no message
  amplification.
- The Kafka subscriber's decoded color, coordinates, and size match the Shapes
  Demo data.
- GREEN Kafka samples appear as circles in Shapes Demo.
- Routing Service reports no plugin-loading, descriptor, serialization, or
  deserialization errors.
- Startup and shutdown can be repeated without manual process cleanup.
- A clean-machine rehearsal succeeds using only this README and the supplied
  scripts.
- The presentation does not depend on old Kafka offsets or pre-existing
  topics.

## Current development-host readiness

The current Windows workstation was inspected on August 5, 2026:

- RTI Connext DDS 7.7.0, Routing Service, and Shapes Demo are installed.
- The installed target architecture is `x64Win64VS2017`.
- Visual Studio 2022 Community is installed.
- CMake 4.0.1, Git, and Docker CLI 26.1.1 are available.
- The Docker daemon is not currently running.
- `protoc` is not installed globally; use
  `RTIGATEWAY_ENABLE_PROTOBUF_BUILD=ON`.

These checks apply only to the development host. The customer demonstration
machine requires its own prerequisite and clean-start validation.

## Clean-room validation instructions

Before presenting to a customer, rehearse the full demonstration on a machine
that has none of this workspace's prior state — either a genuinely fresh
Windows machine/VM, or this same machine with Docker/build artifacts reset to
a known-clean starting point. This validates that nothing about the demo
secretly depends on leftover local state.

### A. Fresh machine / fresh install checklist

If rehearsing on a machine that has never run this demo:

1. Install RTI Connext DDS Professional 7.7.0 (Routing Service + Shapes Demo
   selected) and place a valid license at the default license path.
2. Install Git, CMake 3.10+, and a supported C/C++ toolchain (Visual Studio
   2022 with the "Desktop development with C++" workload, on Windows).
3. Install Docker Desktop and start it; confirm the engine is running with
   `docker info --format "{{.ServerVersion}}"`.
4. Copy or clone this workspace (including `demo/` and, if already cloned,
   `rticonnextdds-gateway/`) onto the machine.
5. Follow **Upstream baseline** and **Build plan** above to clone (if not
   already present), pin to the commit, apply the patch from
   [patches/](patches/README.md), and build/install the Gateway.
   - The patch fixes a noisy benign log line, not a functional bug, so the
     demo will still work without it, but the log will reappear if it is
     skipped.
6. Follow [demo/playbook.md](demo/playbook.md) from **Step 1** onward,
   end-to-end, without skipping any step.

### B. Same-machine clean-state reset

If rehearsing again on this same machine and you want to rule out
leftover-state dependencies (stale containers, offsets, logs, demo-state
files) without a full reinstall:

```powershell
# Stop demo processes, remove the Kafka broker/Control Center containers,
# and delete their volumes (wipes all Kafka topics/offsets/data).
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\fherman\Documents\kafka-proto-buff-adapter\demo\scripts\Stop-Demo.ps1"
Set-Location "C:\Users\fherman\Documents\kafka-proto-buff-adapter\demo\docker"
docker compose down -v

# Confirm no demo containers or processes remain.
docker ps -a --filter name=kafka-shapes-protobuf
Get-Process rtiroutingservice, rtishapesdemo, shapes_kafka_publisher, shapes_kafka_subscriber -ErrorAction SilentlyContinue

# Clear prior demo logs and state so nothing from a previous run is reused.
Remove-Item "C:\Users\fherman\Documents\kafka-proto-buff-adapter\demo\logs\*.log", `
    "C:\Users\fherman\Documents\kafka-proto-buff-adapter\demo\logs\demo-state.json" `
    -ErrorAction SilentlyContinue
```

Then follow [demo/playbook.md](demo/playbook.md) from **Step 1** onward. This
recreates the broker container, network, and topics from scratch (matching
what a fresh machine would produce), while reusing the already-built Gateway
artifacts.

### Sign-off

A clean-room rehearsal is considered successful only when every item in
**Acceptance criteria** above holds, using nothing beyond this README,
[demo/playbook.md](demo/playbook.md), and the scripts in `demo/scripts/`.

## Adapting the demo to your own DDS type

The demo ships wired end-to-end for `ShapeType`. To bridge a different DDS
topic/type through Kafka instead, four things must agree with each other:
your DDS IDL, the Protobuf `.proto` message, the Routing Service XML
`<types>` block, and (if you keep using them) the example Kafka
publisher/subscriber apps. Work through these steps in order.

### 1. Confirm your DDS type's exact shape

- Find the `.idl` file that defines your topic's type, e.g. `MyType.idl`.
- Note every member's name, DDS type, and whether it is a key
  (`@key`/`//@key`), plus the fully qualified type name if it lives in a
  module, e.g. `MyModule::MyType`.
- Optionally generate an XML view of the type to double-check field names
  and ordering: `rtiddsgen -convertToXml MyType.idl`.

### 2. Author a matching `.proto` message

Create a new file, e.g. `demo/config/custom/my_type.proto`, with a `message`
whose name is your DDS type's fully-qualified name with `::` replaced by `.`
(e.g. `MyModule.MyType`), and one field per DDS member. The Protobuf
transformation plugin maps types as follows:

| DDS type | Protobuf type |
| --- | --- |
| `long`, `short`, `int8`, `char`, `int32` | `int32`, `sint32`, `sfixed32` |
| `long long`, `int64` | `int64`, `sint64`, `sfixed64` |
| `unsigned long`, `unsigned short`, `octet`, `uint32` | `uint32`, `fixed32` |
| `unsigned long long`, `uint64` | `uint64`, `fixed64` |
| `float` / `double` | `float` / `double` |
| `boolean` | `bool` |
| `string` | `string` |
| `T[N]` / `sequence<T>` | `repeated T` |
| `struct` | `message` |
| `enum` | `enum` |

Notes:

- `wchar`/`wstring` and `union` are not supported by the transformation.
- Field numbers in the `.proto` (the `= 1`, `= 2`, ...) can be assigned in any
  order; they do not need to match a DDS `@id`.
- Member names must match between the DDS struct and the Protobuf message
  (case-sensitive); this is how the plugin pairs up fields.

Example, for a DDS type with a `name` (string), `count` (long), and `active`
(boolean):

```protobuf
syntax = "proto3";

message MyType {
    string name = 1;
    int32 count = 2;
    bool active = 3;
}
```

### 3. Generate the descriptor set file

Routing Service reads the Protobuf type from a binary descriptor set, not the
`.proto` source, so it must be (re)generated with `protoc` any time the
`.proto` changes:

```powershell
protoc --descriptor_set_out="demo\config\custom\my_type.pbdesc" `
    --include_imports `
    -I "demo\config\custom" `
    "demo\config\custom\my_type.proto"
```

### 4. Create a customized Routing Service XML

Copy `demo/config/shapesdemo_demo.xml` to a new file (e.g.
`demo/config/my_type_demo.xml`) and update it:

- In `<types>`, replace the `ShapeType` `<struct>` with one matching your DDS
  type's members and keys, e.g.:

  ```xml
  <struct name="MyType" extensibility="extensible">
      <member name="name" stringMaxLength="128" type="string" key="true"/>
      <member name="count" type="long"/>
      <member name="active" type="boolean"/>
  </struct>
  ```

- Replace every `registered_type_name` and `input_type_name` that currently
  reads `ShapeType` with your type's name (participant, connection,
  `dds_input`/`dds_output`, and both `transformation` blocks).
- Replace the `Square`/`Circle` topic name values with your Kafka topic
  name(s).
- Change the `descriptor_file` value in both `transformation` blocks to your
  new `.pbdesc` file's name.
- If your DDS type name (with `::` replaced by `.`) does not exactly match
  your Protobuf message's fully-qualified name, add a `message_type`
  property to the `transformation`'s `<property>` block to specify it
  explicitly.

### 5. Replace RTI Shapes Demo on the DDS side

The current demo uses RTI Shapes Demo as the DDS-side publisher/subscriber,
but Shapes Demo is a fixed application that only knows the built-in
`ShapeType` (Square/Circle/Triangle) — it cannot publish or subscribe an
arbitrary custom type. For a custom type, Shapes Demo must be replaced with
your own DDS application:

- Generate type support code from your `.idl` with `rtiddsgen`, e.g.
  `rtiddsgen -language C++11 -platform x64Win64VS2017 MyType.idl`, and link
  it into a small publisher and subscriber (or add DDS pub/sub calls to an
  existing application) using the Connext DDS API in whatever language you
  prefer.
- Point that application at the same DDS domain ID used by Routing Service
  (`$(DDS_DOMAIN_ID)` / `-DomainId` in `Start-Demo.ps1`) and the same topic
  name(s) configured in the customized XML from step 4.
- Any Connext DDS application works here — it does not need to be built as
  part of this Gateway repository.

### 6. Update or replace the example Kafka apps (optional)

`shapes_kafka_publisher`/`shapes_kafka_subscriber` are compiled against
`shape_type.pb.h`, generated from `shape_type.proto`, and call
type-specific accessors (`shape.set_color(...)`, and so on). Routing Service
itself does not need these apps — they only exist to produce/display test
Kafka traffic. Choose one:

- Copy `rticonnextdds-gateway/examples/kafka/kafka-shapes-protobuf` to a new
  example directory, point its `CMakeLists.txt` at your `.proto` instead of
  `shape_type.proto`, rename the generated target names, and update the
  `srcCxx` sources to call your message's generated accessors.
- Write a minimal producer/consumer in any language capable of serializing
  your Protobuf message and publishing/consuming raw bytes on your Kafka
  topic (no dependency on the Gateway build).

### 7. Update the demo automation scripts (optional)

`Start-Demo.ps1` hardcodes the `shapesdemo_demo.xml` path, the
`shapesdemo_bridge` config name, and the `Square`/`Circle` topic and example
executable names. For a repeatable custom-type demo, copy `Start-Demo.ps1` to
a new script and update `$rsConfigFile`, the example directory/executable
names, and the topic name arguments. Likewise, either extend `Start-Kafka.ps1`
to create your topic name(s) or create them manually after it runs, e.g.:

```powershell
docker exec kafka-shapes-protobuf-broker kafka-topics `
    --create --topic MyTopic --bootstrap-server localhost:9092 `
    --partitions 1 --replication-factor 1
```

### 8. Test end to end

1. Run `Test-Prerequisites.ps1`, then your customized `Start-Kafka.ps1` and
   `Start-Demo.ps1` (or manual equivalents).
2. Check the Routing Service log for successful plugin, type, and descriptor
   loading, and watch for serialization/deserialization errors as you publish
   a sample on each side.
3. Confirm a message published on the DDS side arrives correctly transformed
   on the Kafka side, and vice versa.

## Estimated implementation effort

Allow approximately one working day to build, adapt the configuration, create
the launch scripts, and rehearse locally. Reserve a second day for validation
on a clean or customer-equivalent machine and for resolving compiler, Docker,
license, or network differences.