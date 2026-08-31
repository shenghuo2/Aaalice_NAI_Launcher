#!/usr/bin/env bash
set -euo pipefail

architecture="${1:-}"
version="${2:-}"
app_path="${3:-}"
output_path="${4:-}"

case "$architecture" in
  arm64)
    expected_arch="arm64"
    ;;
  x64)
    expected_arch="x86_64"
    ;;
  *)
    echo "Usage: $0 <arm64|x64> <version> <app-path> <output-dmg>" >&2
    exit 64
    ;;
esac

if [[ -z "$version" || ! -d "$app_path" || "$output_path" != *.dmg ]]; then
  echo "A version, application bundle, and .dmg output path are required." >&2
  exit 64
fi

app_name="$(basename "$app_path")"
public_version="${version%%+*}"
build_version=''
if [[ "$version" == *+* ]]; then
  build_version="${version##*+}"
fi
work_root="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/nai-macos-dmg.XXXXXX")"
staging_dir="$work_root/staging"
mount_dir="$work_root/mount"
mounted=0

cleanup() {
  set +e
  if [[ "$mounted" -eq 1 ]]; then
    hdiutil detach "$mount_dir" -force >/dev/null 2>&1
  fi
  rm -rf -- "$work_root"
}
trap cleanup EXIT

flutter_macos_short_version() {
  local cleaned segment result index
  local -a raw_segments segments
  cleaned="$(printf '%s' "$1" | LC_ALL=C tr -cd '0-9.')"
  IFS='.' read -r -a raw_segments <<< "$cleaned"
  segments=()
  for segment in "${raw_segments[@]}"; do
    if [[ -n "$segment" ]]; then
      segments+=("$segment")
    fi
  done
  while ((${#segments[@]} < 3)); do
    segments+=('0')
  done
  result="${segments[0]}"
  for ((index = 1; index < ${#segments[@]}; index++)); do
    result+=".${segments[index]}"
  done
  printf '%s' "$result"
}

expected_short_version="$(flutter_macos_short_version "$public_version")"

mkdir -p "$staging_dir" "$mount_dir" "$(dirname "$output_path")"
codesign --verify --deep --strict --verbose=2 "$app_path"
ditto "$app_path" "$staging_dir/$app_name"
ln -s /Applications "$staging_dir/Applications"
rm -f -- "$output_path"

hdiutil create \
  -volname "NAI Launcher" \
  -srcfolder "$staging_dir" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "$output_path"

hdiutil attach "$output_path" -readonly -nobrowse -mountpoint "$mount_dir" \
  >/dev/null
mounted=1
packaged_app="$mount_dir/$app_name"
if [[ ! -d "$packaged_app" ]]; then
  echo "Packaged DMG does not contain $app_name at its root." >&2
  exit 1
fi

packaged_version="$(
  /usr/libexec/PlistBuddy \
    -c 'Print :CFBundleShortVersionString' \
    "$packaged_app/Contents/Info.plist"
)"
packaged_build_version="$(
  /usr/libexec/PlistBuddy \
    -c 'Print :CFBundleVersion' \
    "$packaged_app/Contents/Info.plist"
)"
if [[ "$packaged_version" != "$expected_short_version" ]]; then
  echo "Packaged app version mismatch: expected $expected_short_version, found $packaged_version." >&2
  exit 1
fi
if [[ -n "$build_version" && "$packaged_build_version" != "$build_version" ]]; then
  echo "Packaged app build mismatch: expected $build_version, found $packaged_build_version." >&2
  exit 1
fi
codesign --verify --deep --strict --verbose=2 "$packaged_app"

macho_count=0
while IFS= read -r -d '' candidate; do
  if ! file -b "$candidate" | grep -q '^Mach-O'; then
    continue
  fi
  macho_count=$((macho_count + 1))
  actual_archs="$(lipo -archs "$candidate")"
  if [[ "$actual_archs" != "$expected_arch" ]]; then
    echo "DMG contains a non-$expected_arch Mach-O file: $candidate ($actual_archs)" >&2
    exit 1
  fi
done < <(find "$packaged_app" -type f -print0)

if ((macho_count == 0)); then
  echo "No Mach-O files were found in the packaged application." >&2
  exit 1
fi

hdiutil detach "$mount_dir" >/dev/null
mounted=0
echo "Created and verified $architecture DMG: $output_path ($macho_count Mach-O files)"
