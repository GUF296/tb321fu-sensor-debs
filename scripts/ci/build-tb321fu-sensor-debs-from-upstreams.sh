#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd -P)
. "$SCRIPT_DIR/common.sh"

OUTPUT_DIR=${OUTPUT_DIR:-out/tb321fu-sensor-debs}
ARCH=${ARCH:-arm64}
SENSOR_DEB_VERSION=${SENSOR_DEB_VERSION:-20260715.1}
SENSOR_STRIP=${SENSOR_STRIP:-1}
LIBSSC_REPO=${LIBSSC_REPO:-https://github.com/GUF296/libssc.git}
LIBSSC_REF=${LIBSSC_REF:-b7719402d5d45f64d8ac533ff02698fdd84e1edc}
IIO_SENSOR_PROXY_REPO=${IIO_SENSOR_PROXY_REPO:-https://github.com/GUF296/iio-sensor-proxy.git}
IIO_SENSOR_PROXY_REF=${IIO_SENSOR_PROXY_REF:-4054d61222b473c1b172a04faf0677845201ec7f}
HEXAGONRPC_REPO=${HEXAGONRPC_REPO:-https://github.com/GUF296/hexagonrpc.git}
HEXAGONRPC_REF=${HEXAGONRPC_REF:-86d7a139ef35bb2e62ea13bd7b166a1ec08a4b97}
SENSOR_DEVICE_DATA_DIR=${SENSOR_DEVICE_DATA_DIR:-$REPO_ROOT/device-data/hexagonfs}

for command in dpkg git gzip sha256sum tar; do
  ci_require_cmd "$command"
done
[ "$ARCH" = arm64 ] || ci_die "unsupported ARCH=$ARCH"
[[ $SENSOR_DEB_VERSION =~ ^[0-9][0-9A-Za-z.+~_-]{0,63}$ ]] || \
  ci_die "unsafe Debian package/archive version: $SENSOR_DEB_VERSION"
dpkg --validate-version "$SENSOR_DEB_VERSION" || \
  ci_die "invalid Debian package version: $SENSOR_DEB_VERSION"
for revision in "$LIBSSC_REF" "$IIO_SENSOR_PROXY_REF" "$HEXAGONRPC_REF"; do
  [[ $revision =~ ^[0-9a-f]{40}$ ]] || \
    ci_die "upstream revision must be a full lowercase commit: $revision"
done

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/tb321fu-sensor-upstreams.XXXXXX")
cleanup() { ci_safe_rmtree "$work_dir" "${TMPDIR:-/tmp}" tb321fu-sensor-upstreams.; }
trap cleanup EXIT

git_clean() {
  env \
    -u GIT_DIR \
    -u GIT_WORK_TREE \
    -u GIT_INDEX_FILE \
    -u GIT_OBJECT_DIRECTORY \
    -u GIT_ALTERNATE_OBJECT_DIRECTORIES \
    -u GIT_NAMESPACE \
    GIT_CONFIG_NOSYSTEM=1 \
    GIT_CONFIG_GLOBAL=/dev/null \
    GIT_CONFIG_COUNT=0 \
    GIT_NO_REPLACE_OBJECTS=1 \
    git "$@"
}

require_clean_producer_checkout() {
  local revision hidden_flags

  revision=$(git_clean -C "$REPO_ROOT" rev-parse HEAD)
  [[ $revision =~ ^[0-9a-f]{40}$ ]] || ci_die "invalid sensor producer HEAD"
  git_clean -C "$REPO_ROOT" diff-index --quiet HEAD -- ||
    ci_die "dirty tracked sensor producer checkout"
  [ -z "$(git_clean -C "$REPO_ROOT" status --porcelain --untracked-files=all)" ] ||
    ci_die "dirty or untracked sensor producer checkout"
  [ -z "$(git_clean -C "$REPO_ROOT" ls-files -u)" ] ||
    ci_die "sensor producer checkout has unmerged index entries"
  hidden_flags=$(git_clean -C "$REPO_ROOT" ls-files -v | awk '$1 ~ /^[a-zS]$/')
  [ -z "$hidden_flags" ] ||
    ci_die "sensor producer checkout uses assume-unchanged or skip-worktree flags"
  [ -z "$(git_clean -C "$REPO_ROOT" replace -l)" ] ||
    ci_die "sensor producer checkout has Git replacement refs"
  printf '%s\n' "$revision"
}

clone_locked() {
  local repo=$1
  local revision=$2
  local dst=$3

  git_clean init -q "$dst"
  git_clean -C "$dst" remote add origin "$repo"
  git_clean -C "$dst" fetch -q --depth=1 origin "$revision"
  git_clean -C "$dst" checkout -q --detach FETCH_HEAD
  [ "$(git_clean -C "$dst" rev-parse HEAD)" = "$revision" ] || \
    ci_die "upstream commit mismatch for $repo"
  git_clean -C "$dst" diff-index --quiet HEAD -- || \
    ci_die "dirty upstream checkout for $repo"
  [ -z "$(git_clean -C "$dst" status --porcelain --untracked-files=all)" ] || \
    ci_die "untracked upstream files for $repo"
}

[ -d "$SENSOR_DEVICE_DATA_DIR/sensors/registry" ] || ci_die "missing sensor registry data: $SENSOR_DEVICE_DATA_DIR"
[ -d "$SENSOR_DEVICE_DATA_DIR/sensors/config" ] || ci_die "missing sensor config data: $SENSOR_DEVICE_DATA_DIR"
[ -d "$SENSOR_DEVICE_DATA_DIR/socinfo" ] || ci_die "missing sensor socinfo data: $SENSOR_DEVICE_DATA_DIR"
producer_revision_before=$(require_clean_producer_checkout)

source_root="$work_dir/source-root"
baseline_root="$work_dir/baseline-root"
mkdir -p \
  "$source_root/sensor/daily-current" \
  "$baseline_root/usr/local/share/y700-sns"

ci_log "cloning libssc: $LIBSSC_REPO $LIBSSC_REF"
clone_locked "$LIBSSC_REPO" "$LIBSSC_REF" "$source_root/sensor/daily-current/libssc"
ci_log "cloning iio-sensor-proxy: $IIO_SENSOR_PROXY_REPO $IIO_SENSOR_PROXY_REF"
clone_locked "$IIO_SENSOR_PROXY_REPO" "$IIO_SENSOR_PROXY_REF" "$source_root/sensor/daily-current/iio-sensor-proxy"
ci_log "cloning hexagonrpc: $HEXAGONRPC_REPO $HEXAGONRPC_REF"
clone_locked "$HEXAGONRPC_REPO" "$HEXAGONRPC_REF" "$source_root/sensor/daily-current/hexagonrpc"

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
archive_name="tb321fu-sensor-debs_${SENSOR_DEB_VERSION}_${ARCH}.tar.gz"
rm -f -- "$archive_dir/$archive_name" \
  "$archive_dir/SHA256SUMS-archive.txt" \
  "$archive_dir/SOURCE-LOCK.tsv" \
  "$archive_dir/DEVICE-DATA.sha256"

(cd "$SENSOR_DEVICE_DATA_DIR" &&
  LC_ALL=C find . -type f -print0 |
    LC_ALL=C sort -z |
    xargs -0 -r sha256sum --) >"$archive_dir/DEVICE-DATA.sha256"
[ -s "$archive_dir/DEVICE-DATA.sha256" ] || ci_die "empty device-data manifest"
(cd "$SENSOR_DEVICE_DATA_DIR" &&
  sha256sum -c "$archive_dir/DEVICE-DATA.sha256" >/dev/null) || \
  ci_die "device-data manifest self-check failed"

producer_revision=$(require_clean_producer_checkout)
[ "$producer_revision" = "$producer_revision_before" ] ||
  ci_die "sensor producer HEAD changed during the build"
producer_state=clean
{
  printf 'component\trepository\tcommit\n'
  printf 'sensor-producer\t%s\t%s\n' \
    "${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-GUF296/tb321fu-sensor-debs}" \
    "$producer_revision"
  printf 'libssc\t%s\t%s\n' "$LIBSSC_REPO" "$LIBSSC_REF"
  printf 'iio-sensor-proxy\t%s\t%s\n' "$IIO_SENSOR_PROXY_REPO" "$IIO_SENSOR_PROXY_REF"
  printf 'hexagonrpc\t%s\t%s\n' "$HEXAGONRPC_REPO" "$HEXAGONRPC_REF"
  printf 'device-data-manifest\tlocal-tree\t%s\n' \
    "$(sha256sum "$archive_dir/DEVICE-DATA.sha256" | awk '{print $1}')"
  printf 'producer-state\tgit-status\t%s\n' "$producer_state"
} >"$archive_dir/SOURCE-LOCK.tsv"

epoch=$(ci_source_date_epoch)
(cd "$archive_dir" &&
  tar --sort=name --format=gnu --owner=0 --group=0 --numeric-owner \
    --mtime="@$epoch" -cf - \
    ./*.deb SHA256SUMS-y700-sensor-debs.txt SOURCE-LOCK.tsv DEVICE-DATA.sha256 |
    gzip -n >"$archive_name")
(cd "$archive_dir" && sha256sum "./$archive_name" >SHA256SUMS-archive.txt)
ci_log "sensor deb archive ready: $archive_dir/$archive_name"
