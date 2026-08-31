#!/usr/bin/env bash
set -euo pipefail

architecture="${1:-}"
new_app_path="${2:-}"
baseline_archive_url="${3:-}"
baseline_checksums_url="${4:-}"
baseline_asset_name="${5:-}"

case "$architecture" in
  arm64)
    expected_arch="arm64"
    arch_flag="-arm64"
    ;;
  x64)
    expected_arch="x86_64"
    arch_flag="-x86_64"
    ;;
  *)
    echo "Usage: $0 <arm64|x64> <new-app> <baseline-zip-url> <checksums-url> <baseline-asset-name>" >&2
    exit 64
    ;;
esac

if [[ ! -d "$new_app_path" || -z "$baseline_archive_url" || \
      -z "$baseline_checksums_url" || -z "$baseline_asset_name" ]]; then
  echo "The new app and upstream baseline release arguments are required." >&2
  exit 64
fi

test_root="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/nai-macos-upgrade.XXXXXX")"
cleanup() {
  if [[ -n "${marker:-}" && -f "$marker" ]]; then
    rm -f -- "$marker"
  fi
  if [[ -n "${test_root:-}" && -d "$test_root" ]]; then
    rm -rf -- "$test_root"
  fi
}
trap cleanup EXIT

baseline_archive="$test_root/$baseline_asset_name"
baseline_checksums="$test_root/checksums.txt"
baseline_extract="$test_root/upstream"
install_root="$test_root/Applications"
installed_app="$install_root/Aaalice NAI Launcher.app"

mkdir -p "$baseline_extract" "$install_root"
curl --fail --location --retry 3 --show-error --silent \
  --output "$baseline_archive" "$baseline_archive_url"
curl --fail --location --retry 3 --show-error --silent \
  --output "$baseline_checksums" "$baseline_checksums_url"

expected_checksum="$(
  awk -v name="$baseline_asset_name" '$2 == name { print $1 }' \
    "$baseline_checksums" | tr '[:upper:]' '[:lower:]'
)"
if [[ ! "$expected_checksum" =~ ^[0-9a-fA-F]{64}$ ]]; then
  echo "No valid checksum was found for $baseline_asset_name" >&2
  exit 1
fi
actual_checksum="$(shasum -a 256 "$baseline_archive" | awk '{ print $1 }')"
if [[ "$actual_checksum" != "$expected_checksum" ]]; then
  echo "Upstream baseline checksum mismatch." >&2
  exit 1
fi

ditto -x -k "$baseline_archive" "$baseline_extract"
baseline_app="$baseline_extract/Aaalice NAI Launcher.app"
if [[ ! -d "$baseline_app" ]]; then
  echo "Upstream baseline app was not found after extraction." >&2
  exit 1
fi

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"
}

assert_compatible_identity() {
  local candidate="$1"
  local baseline_bundle_id="$2"
  local baseline_name="$3"
  local baseline_executable="$4"

  [[ "$(plist_value "$candidate" CFBundleIdentifier)" == "$baseline_bundle_id" ]]
  [[ "$(plist_value "$candidate" CFBundleName)" == "$baseline_name" ]]
  [[ "$(plist_value "$candidate" CFBundleExecutable)" == "$baseline_executable" ]]
  [[ "$(plist_value "$candidate" CFBundlePackageType)" == "APPL" ]]
}

launch_and_verify() {
  local app="$1"
  local label="$2"
  local executable_name="$3"
  local log_file="$test_root/${label// /-}.log"
  local executable="$app/Contents/MacOS/$executable_name"

  /usr/bin/arch "$arch_flag" "$executable" >"$log_file" 2>&1 &
  local app_pid=$!
  local iteration
  for iteration in {1..20}; do
    sleep 1
    if ! kill -0 "$app_pid" 2>/dev/null; then
      local exit_code=0
      wait "$app_pid" || exit_code=$?
      echo "$label exited during startup with status $exit_code" >&2
      sed -n '1,200p' "$log_file" >&2
      return 1
    fi
  done

  kill "$app_pid"
  for iteration in {1..10}; do
    if ! kill -0 "$app_pid" 2>/dev/null; then
      wait "$app_pid" || true
      echo "$label remained healthy for the startup smoke-test window."
      return 0
    fi
    sleep 1
  done
  kill -9 "$app_pid" 2>/dev/null || true
  wait "$app_pid" 2>/dev/null || true
  echo "$label required forced termination after a successful startup."
}

baseline_bundle_id="$(plist_value "$baseline_app" CFBundleIdentifier)"
baseline_name="$(plist_value "$baseline_app" CFBundleName)"
baseline_executable="$(plist_value "$baseline_app" CFBundleExecutable)"
baseline_version="$(plist_value "$baseline_app" CFBundleShortVersionString)"
new_version="$(plist_value "$new_app_path" CFBundleShortVersionString)"

assert_compatible_identity \
  "$new_app_path" \
  "$baseline_bundle_id" \
  "$baseline_name" \
  "$baseline_executable"
codesign --verify --deep --strict --verbose=2 "$new_app_path"

ditto "$baseline_app" "$installed_app"
codesign --verify --deep --strict --verbose=2 "$installed_app"
baseline_archs="$(lipo -archs "$installed_app/Contents/MacOS/$baseline_executable")"
if [[ " $baseline_archs " != *" $expected_arch "* ]]; then
  echo "The upstream universal app lacks the $expected_arch slice: $baseline_archs" >&2
  exit 1
fi
launch_and_verify "$installed_app" "upstream-universal" "$baseline_executable"

support_dir="$HOME/Library/Application Support/$baseline_bundle_id"
if [[ ! -d "$support_dir" ]]; then
  echo "The upstream app did not initialize its application-support directory during the smoke-test window; creating the upgrade fixture directory."
  mkdir -p "$support_dir"
fi
marker="$support_dir/split-upgrade-compatibility.$$.marker"
marker_value="preserve-$architecture-$baseline_version-to-$new_version"
printf '%s\n' "$marker_value" >"$marker"

mv "$installed_app" "$test_root/upstream-backup.app"
ditto "$new_app_path" "$installed_app"
assert_compatible_identity \
  "$installed_app" \
  "$baseline_bundle_id" \
  "$baseline_name" \
  "$baseline_executable"
codesign --verify --deep --strict --verbose=2 "$installed_app"

installed_archs="$(lipo -archs "$installed_app/Contents/MacOS/$baseline_executable")"
if [[ "$installed_archs" != "$expected_arch" ]]; then
  echo "Replacement executable is not $expected_arch-only: $installed_archs" >&2
  exit 1
fi
launch_and_verify "$installed_app" "split-$architecture" "$baseline_executable"

if [[ "$(sed -n '1p' "$marker")" != "$marker_value" ]]; then
  echo "Application data did not survive the bundle replacement." >&2
  exit 1
fi

echo "Verified upstream $baseline_version universal -> $new_version $architecture replacement."
echo "Bundle ID and application data path remain $baseline_bundle_id."
