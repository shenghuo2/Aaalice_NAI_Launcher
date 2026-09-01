/// macOS DMG 应用内更新脚本生成器。
///
/// 脚本在应用退出后挂载已校验的 DMG，验证应用身份与代码签名，原子备份
/// 现有应用，复制新版本并重新启动。新版本无法启动时会恢复旧应用。
class MacOSUpdateScript {
  MacOSUpdateScript._();

  static String build({
    required int appPid,
    required String version,
    required String dmgPath,
    required String targetAppPath,
    required String mountDirectory,
    required String backupAppPath,
    required String resultPath,
    required String pendingMetadataPath,
    required String logPath,
  }) {
    final publicVersion = version.split('+').first;
    final buildSeparator = version.lastIndexOf('+');
    final buildVersion = buildSeparator < 0
        ? ''
        : version.substring(buildSeparator + 1);
    return _template
        .replaceAll('@@APP_PID@@', appPid.toString())
        .replaceAll('@@VERSION@@', _shellQuote(version))
        .replaceAll(
          '@@EXPECTED_SHORT_VERSION@@',
          _shellQuote(_macOSShortVersion(publicVersion)),
        )
        .replaceAll('@@EXPECTED_BUILD_VERSION@@', _shellQuote(buildVersion))
        .replaceAll('@@DMG_PATH@@', _shellQuote(dmgPath))
        .replaceAll('@@TARGET_APP@@', _shellQuote(targetAppPath))
        .replaceAll('@@MOUNT_DIR@@', _shellQuote(mountDirectory))
        .replaceAll('@@BACKUP_APP@@', _shellQuote(backupAppPath))
        .replaceAll('@@RESULT_PATH@@', _shellQuote(resultPath))
        .replaceAll(
          '@@PENDING_METADATA_PATH@@',
          _shellQuote(pendingMetadataPath),
        )
        .replaceAll('@@LOG_PATH@@', _shellQuote(logPath));
  }

  static String _shellQuote(String value) {
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }

  /// Mirrors Flutter's validatedBuildNameForPlatform rule for macOS.
  static String _macOSShortVersion(String value) {
    final sanitized = value.replaceAll(RegExp(r'[^\d\.]'), '');
    final segments = sanitized
        .split('.')
        .where((segment) => segment.isNotEmpty)
        .toList();
    while (segments.length < 3) {
      segments.add('0');
    }
    return segments.join('.');
  }

  static const _template = r'''#!/bin/bash
set -Eeuo pipefail

AppPid=@@APP_PID@@
Version=@@VERSION@@
DmgPath=@@DMG_PATH@@
TargetApp=@@TARGET_APP@@
MountDir=@@MOUNT_DIR@@
BackupApp=@@BACKUP_APP@@
ResultPath=@@RESULT_PATH@@
PendingMetadataPath=@@PENDING_METADATA_PATH@@
LogPath=@@LOG_PATH@@
ScriptPath="$0"
ResultTemporaryPath="${ResultPath}.tmp.$$"
Mounted=0
Swapped=0
UpdatedExecutablePath=''
UpdatedExecutablePid=''

write_log() {
  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  printf '[%s] %s\n' "$timestamp" "$1" >> "$LogPath"
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  printf '%s' "$value"
}

write_result() {
  local success="$1"
  local message
  message="$(json_escape "$2")"
  printf '{"success":%s,"version":"%s","message":"%s","logPath":"%s"}\n' \
    "$success" \
    "$(json_escape "$Version")" \
    "$message" \
    "$(json_escape "$LogPath")" > "$ResultTemporaryPath"
  mv -f -- "$ResultTemporaryPath" "$ResultPath"
}

cleanup() {
  set +e
  if [[ "$Mounted" -eq 1 ]]; then
    hdiutil detach "$MountDir" -force >> "$LogPath" 2>&1
    Mounted=0
  fi
  rm -rf -- "$MountDir"
  rm -f -- "$ResultTemporaryPath"
  rm -f -- "$ScriptPath"
}

launch_app() {
  local executable_name="$1"
  UpdatedExecutablePath="$TargetApp/Contents/MacOS/$executable_name"
  if [[ ! -x "$UpdatedExecutablePath" ]]; then
    write_log "Updated application executable is not runnable: $UpdatedExecutablePath"
    return 1
  fi

  # `open -n` hands process ownership to LaunchServices. Its helper process can
  # exit before the app settles, which made a healthy update look failed.
  NAI_LAUNCHER_UPDATE_RESTART=1 \
    "$UpdatedExecutablePath" >> "$LogPath" 2>&1 &
  UpdatedExecutablePid=$!
  local iteration
  for iteration in {1..12}; do
    sleep 0.25
    if ! kill -0 "$UpdatedExecutablePid" >/dev/null 2>&1; then
      wait "$UpdatedExecutablePid" || true
      return 1
    fi
  done
  return 0
}

handle_error() {
  local status="$1"
  trap - ERR
  set +e
  local message="macOS update failed at line ${BASH_LINENO[0]} with status $status."
  write_log "$message"
  write_result false "$message"

  if [[ "$Swapped" -eq 1 && -d "$BackupApp" ]]; then
    if [[ -n "$UpdatedExecutablePid" ]]; then
      /bin/kill "$UpdatedExecutablePid" >> "$LogPath" 2>&1 || true
      sleep 0.25
    fi
    rm -rf -- "$TargetApp"
    mv -- "$BackupApp" "$TargetApp"
    Swapped=0
    write_log 'Previous application version restored.'
  fi
  if [[ -d "$TargetApp" ]]; then
    /usr/bin/open -n "$TargetApp" >> "$LogPath" 2>&1 || true
  fi
  exit "$status"
}

trap 'handle_error $?' ERR
trap cleanup EXIT

if [[ "$TargetApp" != *.app || "$TargetApp" == /Volumes/* || \
      "$TargetApp" == *'/AppTranslocation/'* ]]; then
  write_log "Refusing to replace an unsupported app path: $TargetApp"
  false
fi
TargetParent="$(dirname "$TargetApp")"
if [[ ! -d "$TargetApp" || ! -w "$TargetParent" ]]; then
  write_log "Application directory is not replaceable: $TargetParent"
  false
fi
if [[ "$(dirname "$BackupApp")" != "$TargetParent" ]]; then
  write_log 'Backup application must be on the same volume as the installed app.'
  false
fi

write_log "Waiting for application process $AppPid to exit."
Deadline=$((SECONDS + 120))
while kill -0 "$AppPid" >/dev/null 2>&1 && [[ "$SECONDS" -lt "$Deadline" ]]; do
  sleep 0.25
done
sleep 0.5
if kill -0 "$AppPid" >/dev/null 2>&1; then
  write_log "Application process $AppPid did not exit within 120 seconds."
  false
fi

rm -rf -- "$MountDir" "$BackupApp"
mkdir -p -- "$MountDir"
write_log "Mounting verified update image: $DmgPath"
hdiutil attach "$DmgPath" -readonly -nobrowse -mountpoint "$MountDir" \
  >> "$LogPath" 2>&1
Mounted=1

AppBundleName="$(basename "$TargetApp")"
CandidateApp="$MountDir/$AppBundleName"
if [[ ! -d "$CandidateApp" ]]; then
  write_log "Update image does not contain $AppBundleName."
  false
fi

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"
}

CurrentBundleId="$(plist_value "$TargetApp" CFBundleIdentifier)"
CandidateBundleId="$(plist_value "$CandidateApp" CFBundleIdentifier)"
CurrentExecutable="$(plist_value "$TargetApp" CFBundleExecutable)"
CandidateExecutable="$(plist_value "$CandidateApp" CFBundleExecutable)"
CandidateVersion="$(plist_value "$CandidateApp" CFBundleShortVersionString)"
CandidateBuildVersion="$(plist_value "$CandidateApp" CFBundleVersion)"
ExpectedVersion=@@EXPECTED_SHORT_VERSION@@
ExpectedBuildVersion=@@EXPECTED_BUILD_VERSION@@
if [[ -z "$CurrentBundleId" || "$CandidateBundleId" != "$CurrentBundleId" || \
      "$CandidateExecutable" != "$CurrentExecutable" || \
      "$CandidateVersion" != "$ExpectedVersion" || \
      ( -n "$ExpectedBuildVersion" && \
        "$CandidateBuildVersion" != "$ExpectedBuildVersion" ) ]]; then
  write_log 'Update application identity or version does not match the installed app.'
  false
fi
codesign --verify --deep --strict --verbose=2 "$CandidateApp" \
  >> "$LogPath" 2>&1

write_log "Moving current application to backup: $BackupApp"
mv -- "$TargetApp" "$BackupApp"
Swapped=1
/usr/bin/ditto "$CandidateApp" "$TargetApp"
codesign --verify --deep --strict --verbose=2 "$TargetApp" \
  >> "$LogPath" 2>&1

write_log "Starting updated application: $TargetApp"
launch_app "$CurrentExecutable"
write_result true 'Update installed successfully.'

Swapped=0
rm -rf -- "$BackupApp" >> "$LogPath" 2>&1 || \
  write_log "Could not remove update backup: $BackupApp"
if hdiutil detach "$MountDir" >> "$LogPath" 2>&1; then
  Mounted=0
else
  write_log "Could not detach update image: $MountDir"
fi
rm -f -- "$PendingMetadataPath" "$DmgPath" >> "$LogPath" 2>&1 || \
  write_log 'Could not remove one or more downloaded update files.'
write_log 'macOS update completed successfully.'
''';
}
