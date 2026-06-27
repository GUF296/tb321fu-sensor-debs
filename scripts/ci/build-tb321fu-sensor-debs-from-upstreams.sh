#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd -P)
. "$SCRIPT_DIR/common.sh"

OUTPUT_DIR=${OUTPUT_DIR:-out/tb321fu-sensor-debs}
ARCH=${ARCH:-arm64}
SENSOR_DEB_VERSION=${SENSOR_DEB_VERSION:-20260626.1}
SENSOR_STRIP=${SENSOR_STRIP:-1}
LIBSSC_REPO=${LIBSSC_REPO:-https://github.com/GUF296/libssc.git}
LIBSSC_REF=${LIBSSC_REF:-tb321fu-qcom-sns-20260626.1}
IIO_SENSOR_PROXY_REPO=${IIO_SENSOR_PROXY_REPO:-https://github.com/GUF296/iio-sensor-proxy.git}
IIO_SENSOR_PROXY_REF=${IIO_SENSOR_PROXY_REF:-tb321fu-qcom-sns-20260626.1}
HEXAGONRPC_REPO=${HEXAGONRPC_REPO:-https://github.com/GUF296/hexagonrpc.git}
HEXAGONRPC_REF=${HEXAGONRPC_REF:-tb321fu-qcom-sns-20260626.1}
SENSOR_DEVICE_DATA_DIR=${SENSOR_DEVICE_DATA_DIR:-$REPO_ROOT/device-data/hexagonfs}

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/tb321fu-sensor-upstreams.XXXXXX")
cleanup() { rm -rf "$work_dir"; }
trap cleanup EXIT

clone_ref() {
  local repo=$1
  local ref=$2
  local dst=$3
  git clone --depth 1 --branch "$ref" "$repo" "$dst" 2>/dev/null || {
    git clone "$repo" "$dst"
    git -C "$dst" checkout "$ref"
  }
}

[ -d "$SENSOR_DEVICE_DATA_DIR/sensors/registry" ] || ci_die "missing sensor registry data: $SENSOR_DEVICE_DATA_DIR"
[ -d "$SENSOR_DEVICE_DATA_DIR/sensors/config" ] || ci_die "missing sensor config data: $SENSOR_DEVICE_DATA_DIR"
[ -d "$SENSOR_DEVICE_DATA_DIR/socinfo" ] || ci_die "missing sensor socinfo data: $SENSOR_DEVICE_DATA_DIR"

source_root="$work_dir/source-root"
baseline_root="$work_dir/baseline-root"
mkdir -p \
  "$source_root/sensor/daily-current" \
  "$baseline_root/usr/local/share/y700-sns"

ci_log "cloning libssc: $LIBSSC_REPO $LIBSSC_REF"
clone_ref "$LIBSSC_REPO" "$LIBSSC_REF" "$source_root/sensor/daily-current/libssc"
ci_log "cloning iio-sensor-proxy: $IIO_SENSOR_PROXY_REPO $IIO_SENSOR_PROXY_REF"
clone_ref "$IIO_SENSOR_PROXY_REPO" "$IIO_SENSOR_PROXY_REF" "$source_root/sensor/daily-current/iio-sensor-proxy"
ci_log "cloning hexagonrpc: $HEXAGONRPC_REPO $HEXAGONRPC_REF"
clone_ref "$HEXAGONRPC_REPO" "$HEXAGONRPC_REF" "$source_root/sensor/daily-current/hexagonrpc"

cp -a "$SENSOR_DEVICE_DATA_DIR" "$baseline_root/usr/local/share/y700-sns/hexagonfs"

env \
  OUTPUT_DIR="$OUTPUT_DIR" \
  ARCH="$ARCH" \
  SENSOR_DEB_VERSION="$SENSOR_DEB_VERSION" \
  SENSOR_SOURCE_DIR="$source_root" \
  SENSOR_BASELINE_OVERLAY_DIR="$baseline_root" \
  SENSOR_STRIP="$SENSOR_STRIP" \
  bash "$SCRIPT_DIR/build-y700-sensor-debs.sh"

archive_dir=$(cd -- "$OUTPUT_DIR" && pwd -P)
(cd "$archive_dir" && tar -czf "tb321fu-sensor-debs_${SENSOR_DEB_VERSION}_${ARCH}.tar.gz" ./*.deb SHA256SUMS-y700-sensor-debs.txt)
sha256sum "$archive_dir/tb321fu-sensor-debs_${SENSOR_DEB_VERSION}_${ARCH}.tar.gz" > "$archive_dir/SHA256SUMS-archive.txt"
ci_log "sensor deb archive ready: $archive_dir/tb321fu-sensor-debs_${SENSOR_DEB_VERSION}_${ARCH}.tar.gz"
