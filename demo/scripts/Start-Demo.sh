#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=demo-common.sh
. "$SCRIPT_DIR/demo-common.sh"
demo_detect_platform

usage() {
    cat <<'EOF'
Usage: Start-Demo.sh [options]

Options:
  --connext-dir PATH             RTI Connext DDS installation
  --connext-arch NAME            Installed target architecture
  --gateway-install-dir PATH     Gateway install directory
  --bootstrap-servers VALUE      Kafka host:port (default: localhost:9092)
  --domain-id N                  DDS domain ID (default: 0)
  --circle-color COLOR           Published Circle color (default: GREEN)
  --headless                     Do not launch GUI or terminal log windows
  --start-publisher-immediately  Skip the presenter prompt
  -h, --help                     Show this help
EOF
}

connext_dir=""
connext_arch=""
install_dir="$DEMO_GATEWAY_INSTALL"
bootstrap_servers="localhost:9092"
domain_id=0
circle_color="GREEN"
headless=0
start_publisher_immediately=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --connext-dir) connext_dir=${2:?}; shift 2 ;;
        --connext-arch) connext_arch=${2:?}; shift 2 ;;
        --gateway-install-dir) install_dir=${2:?}; shift 2 ;;
        --bootstrap-servers) bootstrap_servers=${2:?}; shift 2 ;;
        --domain-id) domain_id=${2:?}; shift 2 ;;
        --circle-color) circle_color=${2:?}; shift 2 ;;
        --headless) headless=1; shift ;;
        --start-publisher-immediately) start_publisher_immediately=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) demo_die "Unknown option: $1" ;;
    esac
done

case "$domain_id" in
    ''|*[!0-9]*) demo_die "--domain-id must be a non-negative integer." ;;
esac

if [ "$DEMO_PLATFORM" = "Linux" ] && [ "$headless" -ne 1 ]; then
    [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] || \
        demo_die "Interactive Linux launch requires a desktop session. Use --headless over SSH."
    demo_require_command gnome-terminal "Install GNOME Terminal for interactive Ubuntu demo windows."
fi
demo_require_macos_shared_memory

demo_resolve_connext_dir "$connext_dir"
demo_resolve_connext_arch "$connext_arch"
demo_set_artifact_paths "$install_dir"
demo_configure_runtime_environment

rs_config="$DEMO_CONFIG_DIR/shapesdemo_demo.xml"
state_file="$DEMO_LOGS_DIR/demo-state.json"
mkdir -p "$DEMO_LOGS_DIR"

demo_require_dir "$install_dir"
demo_require_dir "$DEMO_CONNEXT_LIB_DIR"
demo_require_dir "$DEMO_CONNEXT_APP_LIB_DIR"
for required in "$DEMO_ROUTING_SERVICE" "$DEMO_KAFKA_ADAPTER" \
    "$DEMO_PROTOBUF_TRANSFORMATION" "$DEMO_DESCRIPTOR" \
    "$DEMO_PUBLISHER" "$DEMO_SUBSCRIBER" "$rs_config"; do
    demo_require_file "$required"
done
if [ "$headless" -ne 1 ]; then
    demo_require_file "$DEMO_SHAPES_DEMO"
fi

if [ -f "$state_file" ]; then
    demo_die "A demo-state.json already exists. Run Stop-Demo.sh before starting another demo."
fi

cp "$DEMO_DESCRIPTOR" "$DEMO_CONFIG_DIR/shape_type.pbdesc"
export KAFKA_BOOTSTRAP_SERVERS=$bootstrap_servers
export DDS_DOMAIN_ID=$domain_id

started_at=$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')
mode="interactive"
[ "$headless" -eq 1 ] && mode="headless"

rs_pid=""; rs_marker=""; rs_path=""
sub_pid=""; sub_marker=""; sub_path=""
pub_pid=""; pub_marker=""; pub_path=""
shapes_pid=""; shapes_marker=""; shapes_path=""
publisher_start_file="$DEMO_LOGS_DIR/.kafka-publisher-start-$$"
publisher_pid_file="$DEMO_LOGS_DIR/.kafka-publisher-$$.pid"
publisher_prompt_pid_file="$DEMO_LOGS_DIR/.kafka-publisher-prompt-$$.pid"
publisher_prompt_pid=""
publisher_window_pid=""; publisher_window_marker=""; publisher_window_path=""
startup_complete=0

add_process_to_plist() {
    local plist key pid marker executable
    plist=$1; key=$2; pid=$3; marker=$4; executable=$5
    [ -n "$pid" ] || return 0
    /usr/bin/plutil -insert "processes.$key" -dictionary "$plist"
    /usr/bin/plutil -insert "processes.$key.pid" -integer "$pid" "$plist"
    /usr/bin/plutil -insert "processes.$key.startMarker" -string "$marker" "$plist"
    /usr/bin/plutil -insert "processes.$key.executablePath" -string "$executable" "$plist"
}

write_state() {
    local plist_tmp json_tmp
    json_tmp="$state_file.tmp"
    if [ "$DEMO_PLATFORM" = "macOS" ]; then
        plist_tmp="$state_file.plist.tmp"
        /usr/bin/plutil -create xml1 "$plist_tmp"
        /usr/bin/plutil -insert schemaVersion -integer 2 "$plist_tmp"
        /usr/bin/plutil -insert startedAt -string "$started_at" "$plist_tmp"
        /usr/bin/plutil -insert platform -string "$DEMO_PLATFORM" "$plist_tmp"
        /usr/bin/plutil -insert architecture -string "$DEMO_ARCHITECTURE" "$plist_tmp"
        /usr/bin/plutil -insert mode -string "$mode" "$plist_tmp"
        /usr/bin/plutil -insert bootstrapServers -string "$bootstrap_servers" "$plist_tmp"
        /usr/bin/plutil -insert domainId -integer "$domain_id" "$plist_tmp"
        /usr/bin/plutil -insert connextDir -string "$DEMO_CONNEXT_DIR" "$plist_tmp"
        /usr/bin/plutil -insert connextArch -string "$DEMO_CONNEXT_ARCH" "$plist_tmp"
        /usr/bin/plutil -insert gatewayInstallDir -string "$install_dir" "$plist_tmp"
        /usr/bin/plutil -insert processes -dictionary "$plist_tmp"
        add_process_to_plist "$plist_tmp" routingService "$rs_pid" "$rs_marker" "$rs_path"
        add_process_to_plist "$plist_tmp" kafkaSubscriber "$sub_pid" "$sub_marker" "$sub_path"
        add_process_to_plist "$plist_tmp" kafkaPublisher "$pub_pid" "$pub_marker" "$pub_path"
        add_process_to_plist "$plist_tmp" shapesDemo "$shapes_pid" "$shapes_marker" "$shapes_path"
        /usr/bin/plutil -convert json -r -o "$json_tmp" "$plist_tmp"
        rm -f "$plist_tmp"
    else
        demo_require_command python3 "Ubuntu 22.04 includes Python 3; restore the base package."
        STATE_STARTED_AT=$started_at \
        STATE_PLATFORM=$DEMO_PLATFORM \
        STATE_ARCHITECTURE=$DEMO_ARCHITECTURE \
        STATE_MODE=$mode \
        STATE_BOOTSTRAP=$bootstrap_servers \
        STATE_DOMAIN=$domain_id \
        STATE_CONNEXT_DIR=$DEMO_CONNEXT_DIR \
        STATE_CONNEXT_ARCH=$DEMO_CONNEXT_ARCH \
        STATE_INSTALL_DIR=$install_dir \
        STATE_RS_PID=$rs_pid STATE_RS_MARKER=$rs_marker STATE_RS_PATH=$rs_path \
        STATE_SUB_PID=$sub_pid STATE_SUB_MARKER=$sub_marker STATE_SUB_PATH=$sub_path \
        STATE_PUB_PID=$pub_pid STATE_PUB_MARKER=$pub_marker STATE_PUB_PATH=$pub_path \
        STATE_PUB_WINDOW_PID=$publisher_window_pid \
        STATE_PUB_WINDOW_MARKER=$publisher_window_marker \
        STATE_PUB_WINDOW_PATH=$publisher_window_path \
        STATE_SHAPES_PID=$shapes_pid STATE_SHAPES_MARKER=$shapes_marker STATE_SHAPES_PATH=$shapes_path \
        python3 - "$json_tmp" <<'PY'
import json
import os
import sys

def process(prefix):
    pid = os.environ.get(prefix + "_PID", "")
    if not pid:
        return None
    return {
        "pid": int(pid),
        "startMarker": os.environ[prefix + "_MARKER"],
        "executablePath": os.environ[prefix + "_PATH"],
    }

processes = {}
for name, prefix in (
    ("routingService", "STATE_RS"),
    ("kafkaSubscriber", "STATE_SUB"),
    ("kafkaPublisher", "STATE_PUB"),
    ("kafkaPublisherWindow", "STATE_PUB_WINDOW"),
    ("shapesDemo", "STATE_SHAPES"),
):
    value = process(prefix)
    if value:
        processes[name] = value

state = {
    "schemaVersion": 2,
    "startedAt": os.environ["STATE_STARTED_AT"],
    "platform": os.environ["STATE_PLATFORM"],
    "architecture": os.environ["STATE_ARCHITECTURE"],
    "mode": os.environ["STATE_MODE"],
    "bootstrapServers": os.environ["STATE_BOOTSTRAP"],
    "domainId": int(os.environ["STATE_DOMAIN"]),
    "connextDir": os.environ["STATE_CONNEXT_DIR"],
    "connextArch": os.environ["STATE_CONNEXT_ARCH"],
    "gatewayInstallDir": os.environ["STATE_INSTALL_DIR"],
    "processes": processes,
}
with open(sys.argv[1], "w", encoding="utf-8") as stream:
    json.dump(state, stream, indent=2)
    stream.write("\n")
PY
    fi
    mv "$json_tmp" "$state_file"
}

register_process() {
    local component pid executable marker
    component=$1; pid=$2; executable=$3
    marker=$(demo_process_start_marker "$pid")
    [ -n "$marker" ] || demo_die "Could not record the start time for $component (PID $pid)."
    case "$component" in
        routingService) rs_pid=$pid; rs_marker=$marker; rs_path=$executable ;;
        kafkaSubscriber) sub_pid=$pid; sub_marker=$marker; sub_path=$executable ;;
        kafkaPublisher) pub_pid=$pid; pub_marker=$marker; pub_path=$executable ;;
        kafkaPublisherWindow)
            publisher_window_pid=$pid
            publisher_window_marker=$marker
            publisher_window_path=$executable
            ;;
        shapesDemo) shapes_pid=$pid; shapes_marker=$marker; shapes_path=$executable ;;
        *) demo_die "Unknown process component: $component" ;;
    esac
    write_state
}

show_macos_log() {
    local title pid stdout_file stderr_file quoted_out quoted_err command escaped
    title=$1; pid=$2; stdout_file=$3; stderr_file=$4
    printf -v quoted_out '%q' "$stdout_file"
    printf -v quoted_err '%q' "$stderr_file"
    command="printf '\\033]0;%s\\007' '$title'; tail -n +1 -f $quoted_out $quoted_err & demo_tail_pid=\$!; while kill -0 $pid 2>/dev/null; do sleep 1; done; kill \$demo_tail_pid 2>/dev/null; wait \$demo_tail_pid 2>/dev/null; exit"
    escaped=${command//\\/\\\\}
    escaped=${escaped//\"/\\\"}
    /usr/bin/osascript \
        -e 'tell application "Terminal"' \
        -e 'activate' \
        -e "do script \"$escaped\"" \
        -e 'end tell' >/dev/null || \
        demo_warn "Could not open the $title log in Terminal.app. Logs remain under $DEMO_LOGS_DIR."
}

show_staged_macos_publisher_log() {
    local title launcher_pid start_file pid_file prompt_pid_file
    local stdout_file stderr_file prompt prompt_deadline
    local quoted_start_file quoted_pid_file quoted_prompt_pid_file
    local quoted_prompt_pid_tmp quoted_out quoted_err quoted_prompt command escaped
    title=$1; launcher_pid=$2; start_file=$3; pid_file=$4
    prompt_pid_file=$5; stdout_file=$6; stderr_file=$7; prompt=$8
    printf -v quoted_start_file '%q' "$start_file"
    printf -v quoted_pid_file '%q' "$pid_file"
    printf -v quoted_prompt_pid_file '%q' "$prompt_pid_file"
    printf -v quoted_prompt_pid_tmp '%q' "$prompt_pid_file.tmp"
    printf -v quoted_out '%q' "$stdout_file"
    printf -v quoted_err '%q' "$stderr_file"
    printf -v quoted_prompt '%q' "$prompt"
    command="printf '%s\\n' \$\$ > $quoted_prompt_pid_tmp; mv $quoted_prompt_pid_tmp $quoted_prompt_pid_file; /usr/bin/clear; printf '\\033]0;%s\\007' '$title'; printf '%s' $quoted_prompt; while kill -0 $launcher_pid 2>/dev/null; do if IFS= read -r -t 1 demo_reply; then : > $quoted_start_file; break; fi; done; if [ ! -e $quoted_start_file ]; then rm -f $quoted_prompt_pid_file $quoted_prompt_pid_tmp; exit; fi; printf '\\nStarting publisher...\\n'; tail -n +1 -f $quoted_out $quoted_err & demo_tail_pid=\$!; while [ ! -s $quoted_pid_file ] && kill -0 $launcher_pid 2>/dev/null; do sleep 1; done; if [ -s $quoted_pid_file ]; then IFS= read -r demo_component_pid < $quoted_pid_file; while kill -0 \$demo_component_pid 2>/dev/null; do sleep 1; done; fi; kill \$demo_tail_pid 2>/dev/null; wait \$demo_tail_pid 2>/dev/null; rm -f $quoted_start_file $quoted_pid_file $quoted_prompt_pid_file $quoted_prompt_pid_tmp; exit"
    escaped=${command//\\/\\\\}
    escaped=${escaped//\"/\\\"}
    if ! /usr/bin/osascript \
        -e 'tell application "Terminal"' \
        -e 'activate' \
        -e "do script \"$escaped\"" \
        -e 'end tell' >/dev/null; then
        demo_warn "Could not open the staged publisher log in Terminal.app. Logs remain under $DEMO_LOGS_DIR."
        return 1
    fi

    prompt_deadline=$((SECONDS + 10))
    while [ ! -s "$prompt_pid_file" ] && [ "$SECONDS" -lt "$prompt_deadline" ]; do
        sleep 0.1
    done
    if [ ! -s "$prompt_pid_file" ]; then
        demo_warn "The staged publisher window did not become ready."
        return 1
    fi
    IFS= read -r publisher_prompt_pid <"$prompt_pid_file"
    case "$publisher_prompt_pid" in
        ''|*[!0-9]*)
            demo_warn "The staged publisher window reported an invalid process ID."
            return 1
            ;;
    esac
    if ! kill -0 "$publisher_prompt_pid" 2>/dev/null; then
        demo_warn "The staged publisher window exited before becoming ready."
        return 1
    fi
}

show_linux_log() {
    local title pid stdout_file stderr_file quoted_out quoted_err command
    title=$1; pid=$2; stdout_file=$3; stderr_file=$4
    printf -v quoted_out '%q' "$stdout_file"
    printf -v quoted_err '%q' "$stderr_file"
    command="tail -n +1 -f $quoted_out $quoted_err & demo_tail_pid=\$!; while kill -0 $pid 2>/dev/null; do sleep 1; done; kill \$demo_tail_pid 2>/dev/null; wait \$demo_tail_pid 2>/dev/null; exit"
    gnome-terminal --title="$title" -- bash -c "$command" >/dev/null 2>&1 || \
        demo_warn "Could not open the $title log in GNOME Terminal. Logs remain under $DEMO_LOGS_DIR."
}

show_staged_linux_publisher_log() {
    local title launcher_pid start_file pid_file prompt_pid_file
    local stdout_file stderr_file prompt prompt_deadline
    local quoted_start_file quoted_pid_file quoted_prompt_pid_file
    local quoted_prompt_pid_tmp quoted_out quoted_err quoted_prompt command
    title=$1; launcher_pid=$2; start_file=$3; pid_file=$4
    prompt_pid_file=$5; stdout_file=$6; stderr_file=$7; prompt=$8
    printf -v quoted_start_file '%q' "$start_file"
    printf -v quoted_pid_file '%q' "$pid_file"
    printf -v quoted_prompt_pid_file '%q' "$prompt_pid_file"
    printf -v quoted_prompt_pid_tmp '%q' "$prompt_pid_file.tmp"
    printf -v quoted_out '%q' "$stdout_file"
    printf -v quoted_err '%q' "$stderr_file"
    printf -v quoted_prompt '%q' "$prompt"
    command="printf '%s\\n' \$\$ > $quoted_prompt_pid_tmp; mv $quoted_prompt_pid_tmp $quoted_prompt_pid_file; clear; printf '%s' $quoted_prompt; while kill -0 $launcher_pid 2>/dev/null; do if IFS= read -r -t 1 demo_reply; then : > $quoted_start_file; break; fi; done; if [ ! -e $quoted_start_file ]; then rm -f $quoted_prompt_pid_file $quoted_prompt_pid_tmp; exit; fi; printf '\\nStarting publisher...\\n'; tail -n +1 -f $quoted_out $quoted_err & demo_tail_pid=\$!; while [ ! -s $quoted_pid_file ] && kill -0 $launcher_pid 2>/dev/null; do sleep 1; done; if [ -s $quoted_pid_file ]; then IFS= read -r demo_component_pid < $quoted_pid_file; while kill -0 \$demo_component_pid 2>/dev/null; do sleep 1; done; fi; kill \$demo_tail_pid 2>/dev/null; wait \$demo_tail_pid 2>/dev/null; rm -f $quoted_start_file $quoted_pid_file $quoted_prompt_pid_file $quoted_prompt_pid_tmp; exit"
    if ! gnome-terminal --title="$title" -- bash -c "$command" >/dev/null 2>&1; then
        demo_warn "Could not open the staged publisher log in GNOME Terminal. Logs remain under $DEMO_LOGS_DIR."
        return 1
    fi

    prompt_deadline=$((SECONDS + 10))
    while [ ! -s "$prompt_pid_file" ] && [ "$SECONDS" -lt "$prompt_deadline" ]; do
        sleep 0.1
    done
    if [ ! -s "$prompt_pid_file" ]; then
        demo_warn "The staged publisher window did not become ready."
        return 1
    fi
    IFS= read -r publisher_prompt_pid <"$prompt_pid_file"
    case "$publisher_prompt_pid" in
        ''|*[!0-9]*)
            demo_warn "The staged publisher window reported an invalid process ID."
            return 1
            ;;
    esac
    if ! kill -0 "$publisher_prompt_pid" 2>/dev/null; then
        demo_warn "The staged publisher window exited before becoming ready."
        return 1
    fi
}

start_logged_component() {
    local component display executable log_base show_log stdout_file stderr_file
    component=$1; display=$2; executable=$3; log_base=$4; show_log=$5
    shift 5
    stdout_file="$DEMO_LOGS_DIR/$log_base.log"
    stderr_file="$DEMO_LOGS_DIR/$log_base.error.log"
    : >"$stdout_file"
    : >"$stderr_file"
    (
        cd "$DEMO_CONFIG_DIR"
        exec env \
            "$DEMO_RUNTIME_LIBRARY_VARIABLE=$DEMO_RUNTIME_LIBRARY_PATH" \
            "KAFKA_BOOTSTRAP_SERVERS=$bootstrap_servers" \
            "DDS_DOMAIN_ID=$domain_id" \
            "$executable" "$@" >>"$stdout_file" 2>>"$stderr_file"
    ) &
    DEMO_LAST_PID=$!
    sleep 0.3
    if ! kill -0 "$DEMO_LAST_PID" 2>/dev/null; then
        tail -n 20 "$stderr_file" >&2 || true
        demo_die "$display exited during startup."
    fi
    register_process "$component" "$DEMO_LAST_PID" "$executable"
    if [ "$show_log" -eq 1 ]; then
        if [ "$DEMO_PLATFORM" = "macOS" ]; then
            show_macos_log "$display" "$DEMO_LAST_PID" "$stdout_file" "$stderr_file"
        else
            show_linux_log "$display" "$DEMO_LAST_PID" "$stdout_file" "$stderr_file"
        fi
    fi
}

cleanup_failed_start() {
    local status
    status=$?
    if [ "$startup_complete" -ne 1 ]; then
        set +e
        [ -n "$pub_pid" ] && demo_stop_owned_process "$pub_pid" "$pub_marker" "$pub_path" 2
        [ -n "$publisher_window_pid" ] && demo_stop_owned_process \
            "$publisher_window_pid" "$publisher_window_marker" "$publisher_window_path" 2
        [ -n "$shapes_pid" ] && demo_stop_owned_process "$shapes_pid" "$shapes_marker" "$shapes_path" 2
        [ -n "$sub_pid" ] && demo_stop_owned_process "$sub_pid" "$sub_marker" "$sub_path" 2
        [ -n "$rs_pid" ] && demo_stop_owned_process "$rs_pid" "$rs_marker" "$rs_path" 2
        rm -f \
            "$publisher_start_file" \
            "$publisher_pid_file" "$publisher_pid_file.tmp" \
            "$publisher_prompt_pid_file" "$publisher_prompt_pid_file.tmp" \
            "$state_file"
        set -e
    fi
    return "$status"
}
trap cleanup_failed_start EXIT

show_logs=0
[ "$headless" -ne 1 ] && show_logs=1

demo_info "Starting Routing Service..."
start_logged_component routingService "Routing Service" "$DEMO_ROUTING_SERVICE" routing_service "$show_logs" \
    -cfgFile "$rs_config" -cfgName shapesdemo_bridge
rs_pid=$DEMO_LAST_PID
sleep 3
kill -0 "$rs_pid" 2>/dev/null || demo_die "Routing Service exited during startup. Review $DEMO_LOGS_DIR."

demo_info "Starting decoded Kafka subscriber on topic 'Square'..."
start_logged_component kafkaSubscriber "Kafka Subscriber (Square)" "$DEMO_SUBSCRIBER" kafka_subscriber "$show_logs" \
    "$bootstrap_servers" Square
sub_pid=$DEMO_LAST_PID

publisher_log_staged=0
if [ "$show_logs" -eq 1 ] && [ "$start_publisher_immediately" -ne 1 ]; then
    publisher_stdout_file="$DEMO_LOGS_DIR/kafka_publisher.log"
    publisher_stderr_file="$DEMO_LOGS_DIR/kafka_publisher.error.log"
    : >"$publisher_stdout_file"
    : >"$publisher_stderr_file"
    rm -f \
        "$publisher_start_file" \
        "$publisher_pid_file" "$publisher_pid_file.tmp" \
        "$publisher_prompt_pid_file" "$publisher_prompt_pid_file.tmp"
    if [ "$DEMO_PLATFORM" = "macOS" ]; then
        if show_staged_macos_publisher_log \
            "Kafka Publisher (Circle) - press Enter to start" \
            "$$" "$publisher_start_file" "$publisher_pid_file" \
            "$publisher_prompt_pid_file" \
            "$publisher_stdout_file" "$publisher_stderr_file" \
            "Press Enter to start publishing $circle_color circles to Kafka topic Circle: "; then
            publisher_log_staged=1
        fi
    elif show_staged_linux_publisher_log \
        "Kafka Publisher (Circle) - press Enter to start" \
        "$$" "$publisher_start_file" "$publisher_pid_file" \
        "$publisher_prompt_pid_file" \
        "$publisher_stdout_file" "$publisher_stderr_file" \
        "Press Enter to start publishing $circle_color circles to Kafka topic Circle: "; then
        register_process kafkaPublisherWindow "$publisher_prompt_pid" "$(command -v bash)"
        publisher_log_staged=1
    fi
fi

if [ "$headless" -ne 1 ]; then
    demo_info "Starting Shapes Demo..."
    template_dir="$DEMO_CONNEXT_DIR/resource/template/rti_workspace/user_config/shapes_demo"
    workspace_dir="$DEMO_LOGS_DIR/shapes-workspace/shapes_demo"
    if [ ! -d "$workspace_dir" ]; then
        mkdir -p "$workspace_dir"
        cp -R "$template_dir"/. "$workspace_dir"/
    fi
    # The installed wrapper also supplies templateDir and workspaceDir. Launch
    # the embedded executable so the state file owns the real GUI process, and
    # use an isolated workspace so clean-room runs do not inherit user state.
    cp "$template_dir/USER_RTI_SHAPES_DEMO_QOS_PROFILES.template.xml" \
        "$workspace_dir/USER_RTI_SHAPES_DEMO_QOS_PROFILES.xml"
    start_logged_component shapesDemo "RTI Shapes Demo" "$DEMO_SHAPES_DEMO" shapes_demo 0 \
        -domainId "$domain_id" -templateDir "$template_dir" -workspaceDir "$workspace_dir"
    shapes_pid=$DEMO_LAST_PID
fi

if [ "$headless" -ne 1 ] && [ "$start_publisher_immediately" -ne 1 ]; then
    demo_info "In Shapes Demo, subscribe to Circle and publish a BLUE Square."
    if [ "$publisher_log_staged" -eq 1 ]; then
        demo_info "Then switch to the Kafka Publisher (Circle) window and press Enter."
        while [ ! -e "$publisher_start_file" ]; do
            if ! kill -0 "$publisher_prompt_pid" 2>/dev/null; then
                demo_die "The staged Kafka publisher window was closed before Enter was pressed."
            fi
            sleep 0.2
        done
    else
        printf 'Press Enter here when ready to publish %s circles to Kafka topic Circle: ' "$circle_color"
        IFS= read -r _
    fi
fi

demo_info "Starting Kafka publisher for '$circle_color' circles on topic 'Circle'..."
publisher_show_log=$show_logs
[ "$publisher_log_staged" -ne 1 ] || publisher_show_log=0
start_logged_component kafkaPublisher "Kafka Publisher (Circle)" "$DEMO_PUBLISHER" kafka_publisher "$publisher_show_log" \
    "$bootstrap_servers" "$circle_color" Circle
pub_pid=$DEMO_LAST_PID
if [ "$publisher_log_staged" -eq 1 ]; then
    printf '%s\n' "$pub_pid" >"$publisher_pid_file.tmp"
    mv "$publisher_pid_file.tmp" "$publisher_pid_file"
fi

write_state
startup_complete=1
demo_info "Demo processes started. State recorded in $state_file."
if [ "$headless" -eq 1 ]; then
    demo_info "Headless mode is running Routing Service, subscriber, and publisher; Shapes Demo was not started."
else
    demo_info "In Shapes Demo: subscribe to Circle, then publish a BLUE Square."
fi
demo_info "Run Stop-Demo.sh when finished."
