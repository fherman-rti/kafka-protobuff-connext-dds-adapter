#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=demo-common.sh
. "$SCRIPT_DIR/demo-common.sh"
demo_detect_platform

usage() {
    cat <<'EOF'
Usage: Start-Kafka.sh [--with-control-center] [--timeout-seconds N]
EOF
}

with_control_center=0
timeout_seconds=90
while [ "$#" -gt 0 ]; do
    case "$1" in
        --with-control-center) with_control_center=1; shift ;;
        --timeout-seconds) timeout_seconds=${2:?}; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) demo_die "Unknown option: $1" ;;
    esac
done

case "$timeout_seconds" in
    ''|*[!0-9]*) demo_die "--timeout-seconds must be a non-negative integer." ;;
esac

demo_require_command docker "Install a Docker-compatible engine, CLI, and Compose v2."
docker info >/dev/null 2>&1 || demo_die "The Docker-compatible engine is not reachable. Start it and retry."
docker compose version >/dev/null 2>&1 || demo_die "Docker Compose v2 is required ('docker compose')."

broker_container="kafka-shapes-protobuf-broker"
topics=(Square Circle)

cd "$DEMO_DOCKER_DIR"
demo_info "Starting Kafka broker (KRaft mode)..."
if [ "$with_control_center" -eq 1 ]; then
    docker compose --profile control-center up -d
else
    docker compose up -d broker
fi

demo_info "Waiting for broker health (timeout ${timeout_seconds}s)..."
deadline=$((SECONDS + timeout_seconds))
healthy=0
while [ "$SECONDS" -lt "$deadline" ]; do
    status=$(docker inspect --format '{{.State.Health.Status}}' "$broker_container" 2>/dev/null || true)
    if [ "$status" = "healthy" ]; then
        healthy=1
        break
    fi
    sleep 2
done
if [ "$healthy" -ne 1 ]; then
    docker logs --tail 100 "$broker_container" || true
    demo_die "Broker did not become healthy within ${timeout_seconds}s."
fi
demo_info "Broker is healthy."

for topic in "${topics[@]}"; do
    demo_info "Creating topic '$topic' (if not present)..."
    docker exec "$broker_container" kafka-topics \
        --bootstrap-server localhost:9092 \
        --create --if-not-exists \
        --topic "$topic" --partitions 1 --replication-factor 1
done

topic_deadline=$((SECONDS + 30))
while :; do
    existing_topics=$(docker exec "$broker_container" kafka-topics \
        --bootstrap-server localhost:9092 --list)
    missing=0
    for topic in "${topics[@]}"; do
        if ! printf '%s\n' "$existing_topics" | grep -Fxq "$topic"; then
            missing=$((missing + 1))
        fi
    done
    [ "$missing" -eq 0 ] && break
    [ "$SECONDS" -lt "$topic_deadline" ] || demo_die "Kafka topics were not visible after creation."
    sleep 1
done

demo_info "Kafka broker ready at localhost:9092 with topics: Square, Circle"
if [ "$with_control_center" -eq 1 ]; then
    demo_info "Control Center available at http://localhost:9021"
fi
