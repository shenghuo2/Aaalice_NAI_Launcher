#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

architecture="${1:-}"
case "$architecture" in
  arm64)
    expected_arch="arm64"
    excluded_arch="x86_64"
    ;;
  x64)
    expected_arch="x86_64"
    excluded_arch="arm64"
    ;;
  *)
    echo "Usage: $0 <arm64|x64>" >&2
    exit 64
    ;;
esac

release_config="macos/Flutter/Flutter-Release.xcconfig"
app_path="build/macos/Build/Products/Release/Aaalice NAI Launcher.app"
config_backup="$(mktemp "${TMPDIR:-/tmp}/nai-launcher-macos-config.XXXXXX")"
app_semver="$(sed -nE 's/^version:[[:space:]]*([^[:space:]]+).*/\1/p' pubspec.yaml)"

if [[ ! "$app_semver" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?\+[0-9]+$ ]]; then
  echo "pubspec.yaml contains an invalid release SemVer: $app_semver" >&2
  exit 1
fi

cp "$release_config" "$config_backup"
restore_config() {
  cp "$config_backup" "$release_config"
  unlink "$config_backup" 2>/dev/null || true
}
trap restore_config EXIT

printf '\n// Set by scripts/build_macos_arch.sh for this build only.\nEXCLUDED_ARCHS = %s\n' \
  "$excluded_arch" >> "$release_config"

flutter build macos \
  --release \
  --no-pub \
  --dart-define="APP_SEMVER=$app_semver"

if [[ ! -d "$app_path" ]]; then
  echo "macOS application bundle was not produced: $app_path" >&2
  exit 1
fi

bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_path/Contents/Info.plist")"
expected_build="${app_semver##*+}"
if [[ "$bundle_version" != "$expected_build" ]]; then
  echo "macOS bundle build number mismatch: expected $expected_build, found $bundle_version" >&2
  exit 1
fi

macho_count=0
thinned_count=0
while IFS= read -r -d '' candidate; do
  if ! file -b "$candidate" | grep -q '^Mach-O'; then
    continue
  fi
  macho_count=$((macho_count + 1))
  actual_archs="$(lipo -archs "$candidate")"
  if [[ " $actual_archs " != *" $expected_arch "* ]]; then
    echo "Missing $expected_arch slice in $candidate: $actual_archs" >&2
    exit 1
  fi

  if [[ "$actual_archs" != "$expected_arch" ]]; then
    temporary_binary="$(mktemp "${candidate}.thin.XXXXXX")"
    lipo "$candidate" -thin "$expected_arch" -output "$temporary_binary"
    chmod "$(stat -f '%Lp' "$candidate")" "$temporary_binary"
    mv -f "$temporary_binary" "$candidate"
    thinned_count=$((thinned_count + 1))
  fi
done < <(find "$app_path" -type f -print0)

if ((macho_count == 0)); then
  echo "No Mach-O binaries were found in $app_path" >&2
  exit 1
fi

codesign --force --deep --sign - \
  --preserve-metadata=identifier,entitlements,requirements,flags,runtime \
  "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"

verified_count=0
while IFS= read -r -d '' candidate; do
  if ! file -b "$candidate" | grep -q '^Mach-O'; then
    continue
  fi
  verified_count=$((verified_count + 1))
  actual_archs="$(lipo -archs "$candidate")"
  if [[ "$actual_archs" != "$expected_arch" ]]; then
    echo "Expected only $expected_arch in $candidate after thinning: $actual_archs" >&2
    exit 1
  fi
done < <(find "$app_path" -type f -print0)

if ((verified_count != macho_count)); then
  echo "Mach-O file count changed during thinning: $macho_count -> $verified_count" >&2
  exit 1
fi

echo "Verified $verified_count Mach-O files as $expected_arch only ($thinned_count thinned)."
