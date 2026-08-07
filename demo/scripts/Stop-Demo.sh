#!/bin/bash
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=demo-common.sh
. "$SCRIPT_DIR/demo-common.sh"
demo_detect_platform

usage() {
    cat <<'EOF'
Usage: Stop-Demo.sh [--skip-kafka] [--grace-seconds N]
EOF
}

skip_kafka=0
grace_seconds=5
while [ "$#" -gt 0 ]; do
    case "$1" in
        --skip-kafka) skip_kafka=1; shift ;;
        --grace-seconds) grace_seconds=${2:?}; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) demo_die "Unknown option: $1" ;;
    esac
done

case "$grace_seconds" in
    ''|*[!0-9]*) demo_die "--grace-seconds must be a non-negative integer." ;;
esac

state_file="$DEMO_LOGS_DIR/demo-state.json"
all_handled=1

state_get() {
    local key
    key=$1
    if [ "$DEMO_PLATFORM" = "macOS" ]; then
        /usr/bin/plutil -extract "$key" raw -n "$state_file"
    else
        python3 - "$state_file" "$key" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    value = json.load(stream)
for part in sys.argv[2].split("."):
    value = value[part]
print(value)
PY
    fi
}

if [ -f "$state_file" ]; then
    if [ "$DEMO_PLATFORM" = "Linux" ]; then
        demo_require_command python3 "Ubuntu 22.04 includes Python 3; restore the base package before cleanup."
    fi
    schema_version=$(state_get schemaVersion 2>/dev/null || true)
    if [ "$schema_version" != "2" ]; then
        demo_warn "The state file is missing the supported schema version; it will be retained."
        all_handled=0
    else
        for component in kafkaPublisher shapesDemo kafkaSubscriber routingService; do
            pid=$(state_get "processes.$component.pid" 2>/dev/null || true)
            [ -n "$pid" ] || continue
            marker=$(state_get "processes.$component.startMarker" 2>/dev/null || true)
            executable=$(state_get "processes.$component.executablePath" 2>/dev/null || true)

            if ! kill -0 "$pid" 2>/dev/null; then
                demo_warn "$component (PID $pid) is not running."
                continue
            fi
            if ! demo_process_matches "$pid" "$marker" "$executable"; then
                demo_warn "Refusing to stop $component: PID $pid no longer matches the recorded process."
                all_handled=0
                continue
            fi

            demo_info "Stopping $component (PID $pid)..."
            demo_stop_owned_process "$pid" "$marker" "$executable" "$grace_seconds"
            result=$?
            if [ "$result" -ne 0 ]; then
                demo_warn "Could not safely stop $component (PID $pid)."
                all_handled=0
            fi
        done
    fi

    if [ "$all_handled" -eq 1 ]; then
        rm -f "$state_file"
    else
        demo_warn "The state file was retained because at least one process could not be safely handled."
    fi
else
    demo_warn "No demo-state.json found; no demo-owned processes need stopping."
fi

if [ "$skip_kafka" -eq 1 ]; then
    demo_warn "Skipping Kafka shutdown (--skip-kafka)."
elif command -v docker >/dev/null 2>&1; then
    demo_info "Stopping Kafka broker and Control Center, if running..."
    (
        cd "$DEMO_DOCKER_DIR"
        docker compose --profile control-center down
    ) || demo_warn "Docker Compose teardown failed."
else
    demo_warn "Docker is not installed; skipping Compose teardown."
fi

if [ "$all_handled" -eq 1 ]; then
    demo_info "Demo stopped."
else
    demo_warn "Demo cleanup completed with ownership or termination warnings."
    exit 1
fi
