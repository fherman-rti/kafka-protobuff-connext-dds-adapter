#!/bin/bash

# Shared native helpers for the macOS and Ubuntu demo workflows. Keep this file
# compatible with the /bin/bash shipped by supported Apple Silicon macOS.

# RTI's recommended minimum macOS System V shared-memory settings. Connext's
# built-in shared-memory transport is enabled by default, including for the
# participants created by Distributed Logger and Monitoring Library 2.0.
DEMO_MACOS_SHMMAX_REQUIRED=419430400
DEMO_MACOS_SHMMNI_REQUIRED=128
DEMO_MACOS_SHMSEG_REQUIRED=1024
DEMO_MACOS_SHMALL_REQUIRED=262144

demo_die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

demo_warn() {
    printf 'WARNING: %s\n' "$*" >&2
}

demo_info() {
    printf '%s\n' "$*"
}

demo_init_paths() {
    DEMO_SCRIPTS_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
    DEMO_ROOT=$(CDPATH= cd -- "$DEMO_SCRIPTS_DIR/.." && pwd)
    DEMO_REPO_ROOT=$(CDPATH= cd -- "$DEMO_ROOT/.." && pwd)
    DEMO_GATEWAY_SOURCE="$DEMO_REPO_ROOT/rticonnextdds-gateway"
    DEMO_GATEWAY_INSTALL="$DEMO_GATEWAY_SOURCE/install"
    DEMO_CONFIG_DIR="$DEMO_ROOT/config"
    DEMO_DOCKER_DIR="$DEMO_ROOT/docker"
    DEMO_LOGS_DIR="$DEMO_ROOT/logs"
}

demo_detect_platform() {
    local kernel machine translated
    kernel=$(/usr/bin/uname -s)
    machine=$(/usr/bin/uname -m)

    case "$kernel" in
        Darwin)
            translated=$(/usr/sbin/sysctl -in sysctl.proc_translated 2>/dev/null || printf '0')
            [ "$machine" = "arm64" ] || demo_die "Apple Silicon ARM64 is required (detected $machine). Intel macOS is not supported."
            [ "$translated" != "1" ] || demo_die "The shell is running under Rosetta. Open a native ARM64 terminal and retry."
            DEMO_PLATFORM="macOS"
            DEMO_ARCHITECTURE="arm64"
            DEMO_SHARED_PREFIX="lib"
            DEMO_SHARED_SUFFIX=".dylib"
            DEMO_RUNTIME_LIBRARY_VARIABLE="DYLD_LIBRARY_PATH"
            ;;
        Linux)
            case "$machine" in
                x86_64|amd64) ;;
                *) demo_die "The Ubuntu workflow requires x64 (detected $machine)." ;;
            esac
            DEMO_PLATFORM="Linux"
            DEMO_ARCHITECTURE="x64"
            DEMO_SHARED_PREFIX="lib"
            DEMO_SHARED_SUFFIX=".so"
            DEMO_RUNTIME_LIBRARY_VARIABLE="LD_LIBRARY_PATH"
            ;;
        *)
            demo_die "This native workflow supports Apple Silicon macOS and x64 Linux (detected $kernel)."
            ;;
    esac
}

demo_require_macos_arm64() {
    demo_detect_platform
    [ "$DEMO_PLATFORM" = "macOS" ] || demo_die "This script currently requires Apple Silicon macOS."
}

demo_require_command() {
    command -v "$1" >/dev/null 2>&1 || demo_die "$1 is not available on PATH. $2"
}

demo_read_macos_shared_memory() {
    DEMO_MACOS_SHMMAX=$(/usr/sbin/sysctl -n kern.sysv.shmmax 2>/dev/null) || return 1
    DEMO_MACOS_SHMMNI=$(/usr/sbin/sysctl -n kern.sysv.shmmni 2>/dev/null) || return 1
    DEMO_MACOS_SHMSEG=$(/usr/sbin/sysctl -n kern.sysv.shmseg 2>/dev/null) || return 1
    DEMO_MACOS_SHMALL=$(/usr/sbin/sysctl -n kern.sysv.shmall 2>/dev/null) || return 1
    [ -n "$DEMO_MACOS_SHMMAX" ] && [ -n "$DEMO_MACOS_SHMMNI" ] &&
        [ -n "$DEMO_MACOS_SHMSEG" ] && [ -n "$DEMO_MACOS_SHMALL" ] || return 1
    case "$DEMO_MACOS_SHMMAX:$DEMO_MACOS_SHMMNI:$DEMO_MACOS_SHMSEG:$DEMO_MACOS_SHMALL" in
        *[!0-9:]*) return 1 ;;
    esac
}

demo_macos_shared_memory_ready() {
    demo_read_macos_shared_memory || return 1
    [ "$DEMO_MACOS_SHMMAX" -ge "$DEMO_MACOS_SHMMAX_REQUIRED" ] &&
        [ "$DEMO_MACOS_SHMMNI" -ge "$DEMO_MACOS_SHMMNI_REQUIRED" ] &&
        [ "$DEMO_MACOS_SHMSEG" -ge "$DEMO_MACOS_SHMSEG_REQUIRED" ] &&
        [ "$DEMO_MACOS_SHMALL" -ge "$DEMO_MACOS_SHMALL_REQUIRED" ]
}

demo_macos_shared_memory_values() {
    printf 'shmmax=%s, shmmni=%s, shmseg=%s, shmall=%s' \
        "${DEMO_MACOS_SHMMAX:-unknown}" "${DEMO_MACOS_SHMMNI:-unknown}" \
        "${DEMO_MACOS_SHMSEG:-unknown}" "${DEMO_MACOS_SHMALL:-unknown}"
}

demo_require_macos_shared_memory() {
    [ "$DEMO_PLATFORM" = "macOS" ] || return 0
    if demo_macos_shared_memory_ready; then
        return 0
    fi
    demo_die "macOS shared-memory limits are below RTI's recommended minimum ($(demo_macos_shared_memory_values)). Run Test-Prerequisites.sh and follow https://community.rti.com/kb/osx510 before starting the demo."
}

demo_resolve_connext_dir() {
    local requested candidate count candidate_root
    requested=${1:-}

    if [ -n "$requested" ]; then
        [ -d "$requested" ] || demo_die "Connext DDS was not found at '$requested'."
        DEMO_CONNEXT_DIR=$(CDPATH= cd -- "$requested" && pwd)
        return
    fi

    if [ -n "${NDDSHOME:-}" ] && [ -d "$NDDSHOME" ]; then
        DEMO_CONNEXT_DIR=$(CDPATH= cd -- "$NDDSHOME" && pwd)
        return
    fi
    if [ -n "${CONNEXTDDS_DIR:-}" ] && [ -d "$CONNEXTDDS_DIR" ]; then
        DEMO_CONNEXT_DIR=$(CDPATH= cd -- "$CONNEXTDDS_DIR" && pwd)
        return
    fi
    count=0
    DEMO_CONNEXT_DIR=""
    if [ "$DEMO_PLATFORM" = "macOS" ]; then
        if [ -d "/Applications/rti_connext_dds-7.7.0" ]; then
            DEMO_CONNEXT_DIR="/Applications/rti_connext_dds-7.7.0"
            return
        fi
        candidate_root="/Applications"
        for candidate in "$candidate_root"/rti_connext_dds-*; do
            [ -d "$candidate" ] || continue
            DEMO_CONNEXT_DIR=$candidate
            count=$((count + 1))
        done
    else
        if [ -d "$HOME/rti_connext_dds-7.7.0" ]; then
            DEMO_CONNEXT_DIR="$HOME/rti_connext_dds-7.7.0"
            return
        fi
        if [ -d "/opt/rti_connext_dds-7.7.0" ]; then
            DEMO_CONNEXT_DIR="/opt/rti_connext_dds-7.7.0"
            return
        fi
        for candidate in "$HOME"/rti_connext_dds-* /opt/rti_connext_dds-*; do
            [ -d "$candidate" ] || continue
            DEMO_CONNEXT_DIR=$candidate
            count=$((count + 1))
        done
    fi
    [ "$count" -eq 1 ] || demo_die "Connext DDS could not be selected automatically. Pass --connext-dir PATH."
}

demo_resolve_connext_arch() {
    local requested candidate count architecture_prefix
    requested=${1:-}

    if [ -n "$requested" ]; then
        [ -d "$DEMO_CONNEXT_DIR/lib/$requested" ] || demo_die "Connext architecture '$requested' is not installed under '$DEMO_CONNEXT_DIR/lib'."
        DEMO_CONNEXT_ARCH=$requested
        return
    fi

    count=0
    DEMO_CONNEXT_ARCH=""
    if [ "$DEMO_PLATFORM" = "macOS" ]; then
        architecture_prefix="arm64Darwin"
    else
        architecture_prefix="x64Linux"
    fi
    for candidate in "$DEMO_CONNEXT_DIR"/lib/"$architecture_prefix"*; do
        [ -d "$candidate" ] || continue
        DEMO_CONNEXT_ARCH=${candidate##*/}
        count=$((count + 1))
    done
    [ "$count" -eq 1 ] || demo_die "A single $DEMO_PLATFORM/$DEMO_ARCHITECTURE Connext architecture could not be discovered. Pass --connext-arch NAME."
}

demo_set_artifact_paths() {
    local install_dir
    install_dir=$1
    DEMO_GATEWAY_LIB_DIR="$install_dir/lib"
    DEMO_EXAMPLE_DIR="$install_dir/examples/kafka/kafka-shapes-protobuf"
    DEMO_EXAMPLE_BIN_DIR="$DEMO_EXAMPLE_DIR/bin"
    DEMO_KAFKA_ADAPTER="$DEMO_GATEWAY_LIB_DIR/${DEMO_SHARED_PREFIX}rtikafkaadapter${DEMO_SHARED_SUFFIX}"
    DEMO_PROTOBUF_TRANSFORMATION="$DEMO_GATEWAY_LIB_DIR/${DEMO_SHARED_PREFIX}rtiprotobuftransf${DEMO_SHARED_SUFFIX}"
    DEMO_DESCRIPTOR="$DEMO_EXAMPLE_DIR/shape_type.pbdesc"
    DEMO_PUBLISHER="$DEMO_EXAMPLE_BIN_DIR/shapes_kafka_publisher"
    DEMO_SUBSCRIBER="$DEMO_EXAMPLE_BIN_DIR/shapes_kafka_subscriber"
    DEMO_CONNEXT_LIB_DIR="$DEMO_CONNEXT_DIR/lib/$DEMO_CONNEXT_ARCH"
    DEMO_CONNEXT_APP_LIB_DIR="$DEMO_CONNEXT_DIR/resource/app/lib/$DEMO_CONNEXT_ARCH"
    DEMO_CONNEXT_APP_BIN_DIR="$DEMO_CONNEXT_DIR/resource/app/bin/$DEMO_CONNEXT_ARCH"
    DEMO_ROUTING_SERVICE="$DEMO_CONNEXT_APP_BIN_DIR/rtiroutingserviceapp"
    if [ "$DEMO_PLATFORM" = "macOS" ]; then
        DEMO_SHAPES_DEMO="$DEMO_CONNEXT_APP_BIN_DIR/RTI Shapes Demo.app/Contents/MacOS/rtishapesdemo"
    else
        DEMO_SHAPES_DEMO="$DEMO_CONNEXT_APP_BIN_DIR/rtishapesdemo"
    fi
}

demo_require_file() {
    [ -f "$1" ] || demo_die "Missing required file: $1"
}

demo_require_dir() {
    [ -d "$1" ] || demo_die "Missing required directory: $1"
}

demo_configure_runtime_environment() {
    local current
    export NDDSHOME=$DEMO_CONNEXT_DIR
    export CONNEXTDDS_DIR=$DEMO_CONNEXT_DIR
    if [ "$DEMO_RUNTIME_LIBRARY_VARIABLE" = "DYLD_LIBRARY_PATH" ]; then
        current=${DYLD_LIBRARY_PATH:-}
    else
        current=${LD_LIBRARY_PATH:-}
    fi
    DEMO_RUNTIME_LIBRARY_PATH="$DEMO_GATEWAY_LIB_DIR:$DEMO_CONNEXT_APP_LIB_DIR:$DEMO_CONNEXT_LIB_DIR"
    if [ -n "$current" ]; then
        DEMO_RUNTIME_LIBRARY_PATH="$DEMO_RUNTIME_LIBRARY_PATH:$current"
    fi
    if [ "$DEMO_RUNTIME_LIBRARY_VARIABLE" = "DYLD_LIBRARY_PATH" ]; then
        export DYLD_LIBRARY_PATH=$DEMO_RUNTIME_LIBRARY_PATH
    else
        export LD_LIBRARY_PATH=$DEMO_RUNTIME_LIBRARY_PATH
    fi
}

demo_validate_native_binary() {
    local description path output
    description=$1
    path=$2
    output=$(/usr/bin/file -L "$path") || demo_die "Could not inspect $path."
    if [ "$DEMO_PLATFORM" = "macOS" ]; then
        printf '%s\n' "$output" | /usr/bin/grep -q 'arm64' || demo_die "$description is not ARM64: $output"
        if printf '%s\n' "$output" | /usr/bin/grep -q 'x86_64'; then
            demo_die "$description contains x86_64 code: $output"
        fi
    else
        printf '%s\n' "$output" | /usr/bin/grep -Eq 'x86-64|x86_64' || demo_die "$description is not x64: $output"
    fi
}

demo_validate_dependencies() {
    local path output validation_library_path
    path=$1
    if [ "$DEMO_PLATFORM" = "macOS" ]; then
        output=$(/usr/bin/otool -L "$path") || demo_die "otool could not inspect $path."
        if printf '%s\n' "$output" | /usr/bin/grep -E '/opt/homebrew|/usr/local|/opt/local' >/dev/null; then
            demo_die "Artifact has a build-host package-manager dependency: $path"
        fi
    else
        validation_library_path="$DEMO_GATEWAY_LIB_DIR:$DEMO_CONNEXT_APP_LIB_DIR:$DEMO_CONNEXT_LIB_DIR"
        if [ -n "${LD_LIBRARY_PATH:-}" ]; then
            validation_library_path="$validation_library_path:$LD_LIBRARY_PATH"
        fi
        output=$(LD_LIBRARY_PATH=$validation_library_path ldd "$path") || demo_die "ldd could not inspect $path."
        if printf '%s\n' "$output" | /usr/bin/grep -q 'not found'; then
            demo_die "Artifact has an unresolved dependency: $path"
        fi
    fi
}

demo_process_start_marker() {
    /bin/ps -p "$1" -o lstart= 2>/dev/null | /usr/bin/sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

demo_process_command() {
    /bin/ps -p "$1" -o comm= 2>/dev/null | /usr/bin/sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

demo_process_matches() {
    local pid expected_marker expected_path actual_marker actual_command
    pid=$1
    expected_marker=$2
    expected_path=$3

    /bin/kill -0 "$pid" 2>/dev/null || return 1
    actual_marker=$(demo_process_start_marker "$pid")
    [ -n "$actual_marker" ] && [ "$actual_marker" = "$expected_marker" ] || return 1
    actual_command=$(demo_process_command "$pid")
    [ -n "$actual_command" ] || return 1
    [ "$actual_command" = "$expected_path" ] || [ "${actual_command##*/}" = "${expected_path##*/}" ]
}

demo_stop_owned_process() {
    local pid marker executable grace elapsed
    pid=$1
    marker=$2
    executable=$3
    grace=${4:-5}

    demo_process_matches "$pid" "$marker" "$executable" || return 2
    /bin/kill -TERM "$pid" 2>/dev/null || return 1
    elapsed=0
    while /bin/kill -0 "$pid" 2>/dev/null && [ "$elapsed" -lt "$grace" ]; do
        /bin/sleep 1
        elapsed=$((elapsed + 1))
    done
    if /bin/kill -0 "$pid" 2>/dev/null; then
        /bin/kill -KILL "$pid" 2>/dev/null || return 1
    fi
    return 0
}

demo_tcp_reachable() {
    if [ "$DEMO_PLATFORM" = "macOS" ]; then
        /usr/bin/nc -z -G "${3:-1}" "$1" "$2" >/dev/null 2>&1
    else
        nc -z -w "${3:-1}" "$1" "$2" >/dev/null 2>&1
    fi
}

demo_init_paths
