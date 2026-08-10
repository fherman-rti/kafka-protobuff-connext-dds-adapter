#!/bin/bash
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=demo-common.sh
. "$SCRIPT_DIR/demo-common.sh"

usage() {
    cat <<'EOF'
Usage: Test-Prerequisites.sh [options]

Options:
  --connext-dir PATH          RTI Connext DDS installation
  --connext-arch NAME         Installed target architecture
  --gateway-install-dir PATH  Gateway install directory
  --bootstrap-servers VALUE   Kafka host:port (default: localhost:9092)
  -h, --help                  Show this help
EOF
}

connext_dir=""
connext_arch=""
install_dir="$DEMO_GATEWAY_INSTALL"
bootstrap_servers="localhost:9092"
failures=0
warnings=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --connext-dir) connext_dir=${2:?}; shift 2 ;;
        --connext-arch) connext_arch=${2:?}; shift 2 ;;
        --gateway-install-dir) install_dir=${2:?}; shift 2 ;;
        --bootstrap-servers) bootstrap_servers=${2:?}; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) demo_die "Unknown option: $1" ;;
    esac
done

check_ok() {
    printf '[ OK ] %s\n' "$1"
}

check_fail() {
    printf '[FAIL] %s - %s\n' "$1" "$2" >&2
    failures=$((failures + 1))
}

check_warn() {
    printf '[WARN] %s - %s\n' "$1" "$2" >&2
    warnings=$((warnings + 1))
}

printf '=== Platform ===\n'
demo_detect_platform
check_ok "$DEMO_PLATFORM $DEMO_ARCHITECTURE host"
check_ok "Native /bin/bash workflow (PowerShell is not required)"

printf '\n=== Connext DDS installation ===\n'
if (demo_resolve_connext_dir "$connext_dir") 2>/dev/null; then
    demo_resolve_connext_dir "$connext_dir"
    check_ok "Connext directory exists ($DEMO_CONNEXT_DIR)"
else
    check_fail "Connext directory exists" "Pass --connext-dir or set NDDSHOME"
fi

if [ -n "${DEMO_CONNEXT_DIR:-}" ]; then
    if (demo_resolve_connext_arch "$connext_arch") 2>/dev/null; then
        demo_resolve_connext_arch "$connext_arch"
        check_ok "Connext architecture discovered ($DEMO_CONNEXT_ARCH)"
        demo_set_artifact_paths "$install_dir"
    else
        check_fail "Connext architecture discovered" "Pass --connext-arch after verifying the installed target"
    fi
fi

if [ -n "${DEMO_CONNEXT_ARCH:-}" ]; then
    for required in "$DEMO_ROUTING_SERVICE" "$DEMO_SHAPES_DEMO"; do
        if [ -f "$required" ]; then
            check_ok "Connext executable present (${required##*/})"
        else
            check_fail "Connext executable present" "Missing $required"
        fi
    done
    if (demo_validate_native_binary "Connext Routing Service" "$DEMO_ROUTING_SERVICE") 2>/dev/null; then
        check_ok "Connext Routing Service is native $DEMO_ARCHITECTURE"
    else
        check_fail "Connext Routing Service architecture" "Expected native $DEMO_ARCHITECTURE"
    fi
fi

if [ "$DEMO_PLATFORM" = "macOS" ]; then
    printf '\n=== Connext shared memory ===\n'
    if demo_macos_shared_memory_ready; then
        check_ok "macOS System V shared-memory limits ($(demo_macos_shared_memory_values))"
    else
        check_fail "macOS System V shared-memory limits" \
            "Detected $(demo_macos_shared_memory_values); apply RTI's recommendations at https://community.rti.com/kb/osx510 and reboot"
    fi
fi

printf '\n=== License ===\n'
license_file=""
if [ -n "${RTI_LICENSE_FILE:-}" ] && [ -f "$RTI_LICENSE_FILE" ]; then
    license_file=$RTI_LICENSE_FILE
elif [ -n "${DEMO_CONNEXT_DIR:-}" ] && [ -f "$DEMO_CONNEXT_DIR/rti_license.dat" ]; then
    license_file="$DEMO_CONNEXT_DIR/rti_license.dat"
fi
if [ -n "$license_file" ]; then
    check_ok "License file found ($license_file)"
else
    check_warn "License file found" "Set RTI_LICENSE_FILE; a configured license server may also be valid"
fi

printf '\n=== Native build tools ===\n'
for command_name in cmake make; do
    if command -v "$command_name" >/dev/null 2>&1; then
        check_ok "$command_name available"
    else
        check_fail "$command_name available" "Install the native build tools"
    fi
done
if [ "$DEMO_PLATFORM" = "macOS" ]; then
    if command -v clang >/dev/null 2>&1; then
        check_ok "Apple Clang available"
    else
        check_fail "Apple Clang available" "Run xcode-select --install"
    fi
else
    if command -v gcc >/dev/null 2>&1; then
        check_ok "GCC available"
    else
        check_fail "GCC available" "Install Ubuntu's build-essential package"
    fi
fi

printf '\n=== Gateway build artifacts ===\n'
if [ -n "${DEMO_CONNEXT_ARCH:-}" ]; then
    for artifact in "$DEMO_KAFKA_ADAPTER" "$DEMO_PROTOBUF_TRANSFORMATION" "$DEMO_DESCRIPTOR" "$DEMO_PUBLISHER" "$DEMO_SUBSCRIBER"; do
        if [ -f "$artifact" ]; then
            check_ok "Build artifact present (${artifact##*/})"
            if [ "$artifact" != "$DEMO_DESCRIPTOR" ]; then
                if (demo_validate_native_binary "Gateway artifact" "$artifact") 2>/dev/null; then
                    check_ok "Native $DEMO_ARCHITECTURE artifact (${artifact##*/})"
                else
                    check_fail "Native artifact (${artifact##*/})" "Wrong or mixed architecture"
                fi
                if (demo_validate_dependencies "$artifact") 2>/dev/null; then
                    check_ok "Dependencies resolve (${artifact##*/})"
                else
                    check_fail "Dependencies resolve (${artifact##*/})" "Inspect with otool -L or ldd"
                fi
            fi
        else
            check_fail "Build artifact present (${artifact##*/})" "Run Build-Gateway.sh"
        fi
    done
    for runtime_dir in "$DEMO_GATEWAY_LIB_DIR" "$DEMO_CONNEXT_APP_LIB_DIR" "$DEMO_CONNEXT_LIB_DIR"; do
        if [ -d "$runtime_dir" ]; then
            check_ok "Runtime library directory present ($runtime_dir)"
        else
            check_fail "Runtime library directory present" "Missing $runtime_dir"
        fi
    done
fi

printf '\n=== Docker ===\n'
docker_ready=0
if command -v docker >/dev/null 2>&1; then
    check_ok "Docker CLI available"
    if docker info >/dev/null 2>&1; then
        check_ok "Docker-compatible engine reachable"
        docker_ready=1
    else
        check_fail "Docker-compatible engine reachable" "Start the selected macOS runtime or Docker Engine"
    fi
    if docker compose version >/dev/null 2>&1; then
        check_ok "Docker Compose v2 available"
    else
        check_fail "Docker Compose v2 available" "Install the docker compose plugin"
    fi
else
    check_fail "Docker CLI available" "Install a Docker-compatible engine, CLI, and Compose v2"
fi

printf '\n=== Ports ===\n'
for port in 9092 9021; do
    port_in_use=0
    if [ "$DEMO_PLATFORM" = "macOS" ]; then
        /usr/sbin/lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1 && port_in_use=1
    else
        ss -ltn 2>/dev/null | grep -Eq "[:.]$port[[:space:]]" && port_in_use=1
    fi
    if [ "$port_in_use" -eq 0 ]; then
        check_ok "Port $port available"
    elif [ "$docker_ready" -eq 1 ] && docker ps --format '{{.Ports}}' | grep -q ":$port->"; then
        check_ok "Port $port already published by Docker"
    else
        check_warn "Port $port available" "The port is already in use"
    fi
done

printf '\n=== Broker connectivity ===\n'
first_server=${bootstrap_servers%%,*}
broker_host=${first_server%:*}
broker_port=${first_server##*:}
if [ -n "$broker_host" ] && [ "$broker_port" -gt 0 ] 2>/dev/null; then
    if demo_tcp_reachable "$broker_host" "$broker_port" 1; then
        check_ok "Kafka broker reachable at $bootstrap_servers"
    else
        check_warn "Kafka broker reachable at $bootstrap_servers" "Run Start-Kafka.sh before Start-Demo.sh"
    fi
else
    check_fail "Kafka bootstrap address" "Expected host:port, received '$bootstrap_servers'"
fi

printf '\n=== Interactive GUI ===\n'
if [ "$DEMO_PLATFORM" = "macOS" ]; then
    if [ -z "${SSH_CONNECTION:-}" ] && command -v osascript >/dev/null 2>&1; then
        check_ok "macOS GUI and Terminal automation available"
    else
        check_warn "macOS GUI session" "Use --headless over SSH"
    fi
else
    if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
        check_ok "Linux desktop display available"
        if command -v gnome-terminal >/dev/null 2>&1; then
            check_ok "GNOME Terminal available for interactive demo windows"
        else
            check_warn "GNOME Terminal available" "Install the gnome-terminal package or use --headless"
        fi
    else
        check_warn "Linux desktop display" "Use --headless over SSH or outside the VM desktop"
    fi
fi

printf '\n%d warning(s), %d failure(s).\n' "$warnings" "$failures"
if [ "$failures" -gt 0 ]; then
    printf 'Prerequisite check FAILED.\n' >&2
    exit 1
fi
printf 'Prerequisite check PASSED.\n'
