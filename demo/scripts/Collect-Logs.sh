#!/bin/bash
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=demo-common.sh
. "$SCRIPT_DIR/demo-common.sh"
demo_detect_platform

usage() {
    cat <<'EOF'
Usage: Collect-Logs.sh [--output-dir PATH]
EOF
}

output_dir="$DEMO_LOGS_DIR/collected"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --output-dir) output_dir=${2:?}; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) demo_die "Unknown option: $1" ;;
    esac
done

timestamp=$(/bin/date '+%Y%m%d-%H%M%S')
collect_dir="$output_dir/$timestamp"
archive_path="$collect_dir.zip"
mkdir -p "$collect_dir"

demo_info "Collecting application logs..."
for log_file in "$DEMO_LOGS_DIR"/*.log; do
    [ -f "$log_file" ] || continue
    cp "$log_file" "$collect_dir/"
done

state_file="$DEMO_LOGS_DIR/demo-state.json"
if [ -f "$state_file" ]; then
    cp "$state_file" "$collect_dir/"
fi

if command -v docker >/dev/null 2>&1; then
    demo_info "Collecting Docker status and broker logs..."
    (
        cd "$DEMO_DOCKER_DIR"
        docker compose logs --no-color broker >"$collect_dir/kafka_broker.log" 2>&1 || true
        docker compose ps >"$collect_dir/docker_compose_ps.txt" 2>&1 || true
    )
else
    printf 'Docker is not installed.\n' >"$collect_dir/docker_unavailable.txt"
fi

if [ -f "$DEMO_CONFIG_DIR/shapesdemo_demo.xml" ]; then
    cp "$DEMO_CONFIG_DIR/shapesdemo_demo.xml" "$collect_dir/"
fi

{
    printf 'collected_at=%s\n' "$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'platform=%s\n' "$DEMO_PLATFORM"
    printf 'architecture=%s\n' "$DEMO_ARCHITECTURE"
    printf 'kernel=%s\n' "$(uname -a)"
    printf 'shell=%s\n' "${BASH_VERSION:-unknown}"
    printf 'runtime_library_variable=%s\n' "$DEMO_RUNTIME_LIBRARY_VARIABLE"
    if command -v cmake >/dev/null 2>&1; then cmake --version | head -n 1; else printf 'cmake=not installed\n'; fi
    if command -v docker >/dev/null 2>&1; then docker --version; else printf 'docker=not installed\n'; fi
    if command -v docker >/dev/null 2>&1; then docker compose version 2>&1 || true; fi
    if [ "$DEMO_PLATFORM" = "macOS" ] && command -v clang >/dev/null 2>&1; then clang --version | head -n 1; fi
    if [ "$DEMO_PLATFORM" = "Linux" ] && command -v gcc >/dev/null 2>&1; then gcc --version | head -n 1; fi
} >"$collect_dir/platform-diagnostics.txt" 2>&1

if [ -d "$DEMO_GATEWAY_INSTALL" ]; then
    resolved_connext=$( (demo_resolve_connext_dir ""; printf '%s' "$DEMO_CONNEXT_DIR") 2>/dev/null || true)
    if [ -n "$resolved_connext" ]; then
        DEMO_CONNEXT_DIR=$resolved_connext
        resolved_arch=$( (demo_resolve_connext_arch ""; printf '%s' "$DEMO_CONNEXT_ARCH") 2>/dev/null || true)
        if [ -n "$resolved_arch" ]; then
            DEMO_CONNEXT_ARCH=$resolved_arch
        fi
    fi
    if [ -n "${DEMO_CONNEXT_ARCH:-}" ]; then
        demo_set_artifact_paths "$DEMO_GATEWAY_INSTALL"
        dependency_report="$collect_dir/native-binary-dependencies.txt"
        for artifact in "$DEMO_KAFKA_ADAPTER" "$DEMO_PROTOBUF_TRANSFORMATION" "$DEMO_PUBLISHER" "$DEMO_SUBSCRIBER"; do
            [ -f "$artifact" ] || continue
            printf '[%s]\n' "$artifact" >>"$dependency_report"
            file "$artifact" >>"$dependency_report" 2>&1
            if [ "$DEMO_PLATFORM" = "macOS" ]; then
                otool -L "$artifact" >>"$dependency_report" 2>&1
            else
                ldd "$artifact" >>"$dependency_report" 2>&1
            fi
            printf '\n' >>"$dependency_report"
        done
    fi
fi

if [ "$DEMO_PLATFORM" = "macOS" ]; then
    /usr/bin/ditto -c -k --norsrc --keepParent "$collect_dir" "$archive_path"
else
    demo_require_command python3 "Ubuntu 22.04 includes Python 3; restore the base package."
    python3 - "$collect_dir" <<'PY'
import shutil
import sys

directory = sys.argv[1]
shutil.make_archive(directory, "zip", root_dir=directory)
PY
fi

demo_info "Logs collected: $collect_dir"
demo_info "Archive created: $archive_path"
