#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=demo-common.sh
. "$SCRIPT_DIR/demo-common.sh"
demo_detect_platform

usage() {
    cat <<'EOF'
Usage: Build-Gateway.sh [options]

Options:
  --connext-dir PATH        RTI Connext DDS installation
  --connext-arch NAME       Installed target architecture
  --build-dir PATH          CMake build directory (b-macos or b-linux)
  --install-dir PATH        Gateway install directory
  -h, --help                Show this help
EOF
}

connext_dir=""
connext_arch=""
if [ "$DEMO_PLATFORM" = "macOS" ]; then
    build_dir="$DEMO_REPO_ROOT/b-macos"
else
    build_dir="$DEMO_REPO_ROOT/b-linux"
fi
install_dir="$DEMO_GATEWAY_INSTALL"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --connext-dir)
            [ "$#" -ge 2 ] || demo_die "--connext-dir requires a value."
            connext_dir=$2
            shift 2
            ;;
        --connext-arch)
            [ "$#" -ge 2 ] || demo_die "--connext-arch requires a value."
            connext_arch=$2
            shift 2
            ;;
        --build-dir)
            [ "$#" -ge 2 ] || demo_die "--build-dir requires a value."
            build_dir=$2
            shift 2
            ;;
        --install-dir)
            [ "$#" -ge 2 ] || demo_die "--install-dir requires a value."
            install_dir=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            demo_die "Unknown option: $1"
            ;;
    esac
done

demo_require_command cmake "Install CMake and open a new terminal."
if [ "$DEMO_PLATFORM" = "macOS" ]; then
    demo_require_command clang "Install Apple's command-line developer tools with 'xcode-select --install'."
else
    demo_require_command gcc "Install Ubuntu's build-essential package."
fi
demo_resolve_connext_dir "$connext_dir"
demo_resolve_connext_arch "$connext_arch"
demo_set_artifact_paths "$install_dir"

demo_require_file "$DEMO_GATEWAY_SOURCE/CMakeLists.txt"

demo_info "Platform: $DEMO_PLATFORM $DEMO_ARCHITECTURE"
demo_info "Connext: $DEMO_CONNEXT_DIR [$DEMO_CONNEXT_ARCH]"
demo_info "Configuring the vendored Gateway source in $build_dir..."

configure_args=(
    -S "$DEMO_GATEWAY_SOURCE"
    -B "$build_dir"
    -G "Unix Makefiles"
    -DCMAKE_BUILD_TYPE=Release
    -DCONNEXTDDS_DIR="$DEMO_CONNEXT_DIR"
    -DCONNEXTDDS_ARCH="$DEMO_CONNEXT_ARCH"
    -DCMAKE_INSTALL_PREFIX="$install_dir"
    -DRTIGATEWAY_ENABLE_ALL=OFF
    -DRTIGATEWAY_ENABLE_KAFKA=ON
    -DRTIGATEWAY_ENABLE_TSFM_PROTOBUF=ON
    -DRTIGATEWAY_ENABLE_EXAMPLES=ON
    -DRTIGATEWAY_ENABLE_PROTOBUF_BUILD=ON
    -DRTIGATEWAY_ENABLE_TESTS=OFF
    -DWITH_ZSTD=OFF
    -DENABLE_LZ4_EXT=OFF
)
if [ "$DEMO_PLATFORM" = "macOS" ]; then
    configure_args+=( -DCMAKE_OSX_ARCHITECTURES=arm64 )
fi
cmake "${configure_args[@]}"

demo_info "Building and installing the Gateway demo components..."
cmake --build "$build_dir" --target install --parallel

demo_set_artifact_paths "$install_dir"
demo_require_file "$DEMO_KAFKA_ADAPTER"
demo_require_file "$DEMO_PROTOBUF_TRANSFORMATION"
demo_require_file "$DEMO_DESCRIPTOR"
demo_require_file "$DEMO_PUBLISHER"
demo_require_file "$DEMO_SUBSCRIBER"

for artifact in "$DEMO_GATEWAY_LIB_DIR"/*"$DEMO_SHARED_SUFFIX" "$DEMO_PUBLISHER" "$DEMO_SUBSCRIBER"; do
    [ -f "$artifact" ] || continue
    demo_validate_native_binary "Gateway artifact" "$artifact"
    demo_validate_dependencies "$artifact"
done

demo_info "Gateway build and installation completed: $install_dir"
