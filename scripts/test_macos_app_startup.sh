#!/usr/bin/env bash
set -euo pipefail

architecture="${1:-}"
app_path="${2:-}"
label="${3:-macOS application}"
healthy_seconds="${4:-20}"

case "$architecture" in
  arm64)
    arch_flag="-arm64"
    ;;
  x64)
    arch_flag="-x86_64"
    ;;
  *)
    echo "Usage: $0 <arm64|x64> <app-path> [label] [healthy-seconds]" >&2
    exit 64
    ;;
esac

if [[ ! -d "$app_path" || ! "$healthy_seconds" =~ ^[1-9][0-9]*$ ]]; then
  echo "A valid application bundle and health window are required." >&2
  exit 64
fi

executable_name="$(
  /usr/libexec/PlistBuddy \
    -c 'Print :CFBundleExecutable' \
    "$app_path/Contents/Info.plist"
)"
executable="$app_path/Contents/MacOS/$executable_name"
if [[ ! -x "$executable" ]]; then
  echo "$label executable is not runnable: $executable" >&2
  exit 1
fi

log_file="$(mktemp "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/nai-macos-startup.XXXXXX.log")"
app_pid=''
cleanup() {
  set +e
  if [[ -n "$app_pid" ]] && kill -0 "$app_pid" 2>/dev/null; then
    kill "$app_pid" 2>/dev/null
    sleep 1
    kill -9 "$app_pid" 2>/dev/null || true
  fi
  if [[ -n "$app_pid" ]]; then
    wait "$app_pid" 2>/dev/null || true
  fi
  rm -f -- "$log_file"
}
trap cleanup EXIT

/usr/bin/arch "$arch_flag" "$executable" >"$log_file" 2>&1 &
app_pid=$!

for ((second = 1; second <= healthy_seconds; second++)); do
  sleep 1
  if ! kill -0 "$app_pid" 2>/dev/null; then
    exit_code=0
    wait "$app_pid" || exit_code=$?
    app_pid=''
    echo "$label exited during startup after ${second}s with status $exit_code." >&2
    sed -n '1,240p' "$log_file" >&2
    exit 1
  fi
done

kill "$app_pid"
for _ in {1..10}; do
  if ! kill -0 "$app_pid" 2>/dev/null; then
    wait "$app_pid" 2>/dev/null || true
    app_pid=''
    echo "$label remained healthy for ${healthy_seconds}s."
    exit 0
  fi
  sleep 1
done

kill -9 "$app_pid" 2>/dev/null || true
wait "$app_pid" 2>/dev/null || true
app_pid=''
echo "$label remained healthy for ${healthy_seconds}s and required forced test cleanup."
