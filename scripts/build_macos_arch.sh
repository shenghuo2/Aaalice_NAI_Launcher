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

cp "$release_config" "$config_backup"
restore_config() {
  cp "$config_backup" "$release_config"
  unlink "$config_backup" 2>/dev/null || true
}
trap restore_config EXIT

printf '\n// Set by scripts/build_macos_arch.sh for this build only.\nEXCLUDED_ARCHS = %s\n' \
  "$excluded_arch" >> "$release_config"

flutter build macos --release --no-pub

if [[ ! -d "$app_path" ]]; then
  echo "macOS application bundle was not produced: $app_path" >&2
  exit 1
fi

macho_count=0
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
  for actual_arch in $actual_archs; do
    if [[ "$actual_arch" != "$expected_arch" ]]; then
      echo "Unexpected $actual_arch slice in $candidate: $actual_archs" >&2
      exit 1
    fi
  done
done < <(find "$app_path" -type f -print0)

if ((macho_count == 0)); then
  echo "No Mach-O binaries were found in $app_path" >&2
  exit 1
fi

echo "Verified $macho_count Mach-O files as $expected_arch only."
