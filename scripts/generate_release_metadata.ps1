param(
  [Parameter(Mandatory = $true)]
  [string]$AssetDirectory,

  [string]$OutputDirectory,

  [Parameter(Mandatory = $true)]
  [string]$Version,

  [Parameter(Mandatory = $true)]
  [string]$Tag,

  [Parameter(Mandatory = $true)]
  [string]$Repository
)

$ErrorActionPreference = 'Stop'

function Get-AssetInfo {
  param([System.IO.FileInfo]$File)

  $name = $File.Name
  if ($name -match '_Windows_x64_.*_Setup\.exe$') {
    return [ordered]@{
      platform = 'windows-x64'
      type = 'windows-x64-installer'
      label = 'Windows x64 安装版'
      description = '适用于 64 位 Windows，推荐普通用户使用，支持应用内一键更新。'
    }
  }
  if ($name -match '_Windows_x64_.*_Portable\.zip$') {
    return [ordered]@{
      platform = 'windows-x64'
      type = 'windows-x64-portable'
      label = 'Windows x64 便携版'
      description = '适用于 64 位 Windows，解压即用并支持应用内更新。'
    }
  }
  if ($name -match '_Windows_.*_Setup\.exe$') {
    return [ordered]@{
      platform = 'windows'
      type = 'windows-installer'
      label = 'Windows 安装版'
      description = '推荐普通用户使用，支持应用内一键更新。'
    }
  }
  if ($name -match '_Windows_.*_Portable\.zip$') {
    return [ordered]@{
      platform = 'windows'
      type = 'windows-portable'
      label = 'Windows 便携版'
      description = '解压即用，支持应用内一键更新，适合放在自定义目录。'
    }
  }
  if ($name -match '_macOS_arm64_.*\.dmg$') {
    return [ordered]@{
      platform = 'macos'
      type = 'macos-arm64-dmg'
      label = 'macOS Apple Silicon DMG'
      description = '适用于 Apple Silicon（M 系列）Mac，支持应用内自动替换并重启。'
    }
  }
  if ($name -match '_macOS_x64_.*\.dmg$') {
    return [ordered]@{
      platform = 'macos'
      type = 'macos-x64-dmg'
      label = 'macOS Intel DMG'
      description = '适用于 Intel Mac，支持应用内自动替换并重启。'
    }
  }
  if ($name -match '_macOS_arm64_.*_Portable\.zip$') {
    return [ordered]@{
      platform = 'macos'
      type = 'macos-arm64-portable'
      label = 'macOS Apple Silicon 便携版'
      description = '适用于 Apple Silicon（M 系列）Mac，解压后打开应用。'
    }
  }
  if ($name -match '_macOS_x64_.*_Portable\.zip$') {
    return [ordered]@{
      platform = 'macos'
      type = 'macos-x64-portable'
      label = 'macOS Intel 便携版'
      description = '适用于 Intel Mac，解压后打开应用。'
    }
  }
  if ($name -match '_Android_arm64-v8a_.*\.apk$') {
    return [ordered]@{
      platform = 'android-arm64-v8a'
      type = 'android-arm64-v8a-apk'
      label = 'Android ARM64 APK'
      description = '适用于大多数 64 位 ARM Android 手机和平板。'
    }
  }
  if ($name -match '_Android_armeabi-v7a_.*\.apk$') {
    return [ordered]@{
      platform = 'android-armeabi-v7a'
      type = 'android-armeabi-v7a-apk'
      label = 'Android ARMv7 APK'
      description = '适用于较旧的 32 位 ARM Android 设备。'
    }
  }
  if ($name -match '_Android_x86_64_.*\.apk$') {
    return [ordered]@{
      platform = 'android-x86_64'
      type = 'android-x86_64-apk'
      label = 'Android x86_64 APK'
      description = '适用于 x86_64 Android 设备和模拟器。'
    }
  }
  if ($name -match '_Android_.*\.apk$') {
    return [ordered]@{
      platform = 'android'
      type = 'android-apk'
      label = 'Android APK'
      description = '下载后由 Android 系统确认并安装更新。'
    }
  }
  return $null
}

function Get-ChangelogSection {
  param([string]$Version)

  $changelogPath = Join-Path (Resolve-Path ".") "CHANGELOG.md"
  if (-not (Test-Path -LiteralPath $changelogPath)) {
    return "本次发布见 CHANGELOG.md。"
  }

  $lines = Get-Content -Path $changelogPath -Encoding UTF8
  $headerPattern = '^##\s+(\[)?v?' + [regex]::Escape($Version) + '(\])?(\s|$)'
  $start = -1
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match $headerPattern) {
      $start = $i + 1
      break
    }
  }

  if ($start -lt 0) {
    return "本次发布见 CHANGELOG.md。"
  }

  $end = $lines.Count
  for ($i = $start; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^##\s+') {
      $end = $i
      break
    }
  }

  $section = $lines[$start..($end - 1)] -join [Environment]::NewLine
  if ([string]::IsNullOrWhiteSpace($section)) {
    return "本次发布见 CHANGELOG.md。"
  }
  return $section.Trim()
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
  $OutputDirectory = $AssetDirectory
}

$assetPath = Resolve-Path $AssetDirectory
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$outputPath = Resolve-Path $OutputDirectory

$releaseFiles = Get-ChildItem -Path $assetPath -File |
  Where-Object { $_.Extension -in @('.exe', '.zip', '.dmg', '.apk') } |
  Sort-Object Name

if (-not $releaseFiles) {
  throw "No release assets were found in $assetPath"
}

$assets = @()
$checksumLines = @()
foreach ($file in $releaseFiles) {
  $assetInfo = Get-AssetInfo -File $file
  if (-not $assetInfo) {
    throw "Unknown release asset type: $($file.Name)"
  }

  $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
  $downloadUrl = "https://github.com/$Repository/releases/download/$Tag/$([uri]::EscapeDataString($file.Name))"
  $checksumLines += "$hash  $($file.Name)"
  $assets += [ordered]@{
    platform = $assetInfo.platform
    type = $assetInfo.type
    fileName = $file.Name
    downloadUrl = $downloadUrl
    sha256 = $hash
    size = $file.Length
    label = $assetInfo.label
    description = $assetInfo.description
  }
}

$changelogSection = Get-ChangelogSection -Version ($Version -replace '\+.*$', '')
$manifest = [ordered]@{
  version = $Version
  tag = $Tag
  name = "NAI Launcher $Tag"
  publishedAt = (Get-Date).ToUniversalTime().ToString('o')
  releaseNotes = $changelogSection
  assets = $assets
}

$manifestPath = Join-Path $outputPath "release_manifest.json"
$checksumsPath = Join-Path $outputPath "checksums.txt"
$notesPath = Join-Path $outputPath "release_notes_${Tag}.md"

$manifest |
  ConvertTo-Json -Depth 6 |
  Set-Content -Path $manifestPath -Encoding UTF8
$checksumLines |
  Set-Content -Path $checksumsPath -Encoding UTF8

function Get-DownloadBadge {
  param([System.Collections.IDictionary]$Asset)

  $type = $Asset['type']
  $url = $Asset['downloadUrl']
  switch ($type) {
    'windows-installer' {
      return "[![Windows Setup x64](https://img.shields.io/badge/Setup-x64-0078D4?style=flat-square&logo=windows11&logoColor=white)]($url)"
    }
    'windows-portable' {
      return "[![Windows Portable x64](https://img.shields.io/badge/Portable-x64-56B4D3?style=flat-square&logo=windows11&logoColor=white)]($url)"
    }
    'windows-x64-installer' {
      return "[![Windows Setup x64](https://img.shields.io/badge/Setup-x64-0078D4?style=flat-square&logo=windows11&logoColor=white)]($url)"
    }
    'windows-x64-portable' {
      return "[![Windows Portable x64](https://img.shields.io/badge/Portable-x64-56B4D3?style=flat-square&logo=windows11&logoColor=white)]($url)"
    }
    'macos-arm64-portable' {
      return "[![macOS Apple Silicon](https://img.shields.io/badge/Apple_Silicon-arm64-555555?style=flat-square&logo=apple&logoColor=white)]($url)"
    }
    'macos-x64-portable' {
      return "[![macOS Intel](https://img.shields.io/badge/Intel-x64-777777?style=flat-square&logo=apple&logoColor=white)]($url)"
    }
    'macos-arm64-dmg' {
      return "[![macOS Apple Silicon DMG](https://img.shields.io/badge/DMG-Apple_Silicon-555555?style=flat-square&logo=apple&logoColor=white)]($url)"
    }
    'macos-x64-dmg' {
      return "[![macOS Intel DMG](https://img.shields.io/badge/DMG-Intel-777777?style=flat-square&logo=apple&logoColor=white)]($url)"
    }
    'android-apk' {
      return "[![Android Universal](https://img.shields.io/badge/Android-Universal-3DDC84?style=flat-square&logo=android&logoColor=white)]($url)"
    }
    'android-arm64-v8a-apk' {
      return "[![Android ARM64](https://img.shields.io/badge/Android-ARM64-3DDC84?style=flat-square&logo=android&logoColor=white)]($url)"
    }
    'android-armeabi-v7a-apk' {
      return "[![Android ARMv7](https://img.shields.io/badge/Android-ARMv7-3DDC84?style=flat-square&logo=android&logoColor=white)]($url)"
    }
    'android-x86_64-apk' {
      return "[![Android x86_64](https://img.shields.io/badge/Android-x86__64-3DDC84?style=flat-square&logo=android&logoColor=white)]($url)"
    }
    default {
      throw "Cannot create download badge for asset type: $type"
    }
  }
}

$windowsBadges = @(
  $assets |
    Where-Object { $_['platform'] -like 'windows*' } |
    ForEach-Object { Get-DownloadBadge -Asset $_ }
)
$macosBadges = @(
  $assets |
    Where-Object { $_['platform'] -eq 'macos' } |
    ForEach-Object { Get-DownloadBadge -Asset $_ }
)
$androidBadges = @(
  $assets |
    Where-Object { $_['platform'] -eq 'android' } |
    ForEach-Object { Get-DownloadBadge -Asset $_ }
)
$downloadRows = @()
if ($windowsBadges.Count -gt 0) {
  $downloadRows += "| **Windows** | $($windowsBadges -join '<br>') |"
}
if ($macosBadges.Count -gt 0) {
  $downloadRows += "| **macOS** | $($macosBadges -join '<br>') |"
}
if ($androidBadges.Count -gt 0) {
  $downloadRows += "| **Android** | $($androidBadges -join '<br>') |"
}
$releaseLines = @(
  "# NAI Launcher $Tag",
  "",
  "## 📥 按系统下载",
  "",
  "点击对应按钮直接下载：",
  "",
  "| OS | Download |",
  "| --- | --- |"
)
$releaseLines += $downloadRows
$releaseLines += @(
  "",
  "> **应用内更新：** Windows 会自动选择 x64 Setup/Portable，macOS 会选择匹配芯片的 DMG，Android 会选择设备 ABI；下载完成后均校验文件大小与 SHA256。Windows 与 macOS 随后自动替换并重启，Android 交给系统确认安装。",
  "",
  "> **安装提示：** Android 通常选择 ARM64，只有旧 32 位 ARM 设备使用 ARMv7，模拟器可能使用 x86_64；Universal 用于旧版客户端兼容升级。macOS 首次安装请按芯片选择 Apple Silicon 或 Intel DMG，并将应用放到“应用程序”或其他可写目录。Windows 当前只提供 x64。",
  "",
  "## 📝 更新内容",
  "",
  $changelogSection,
  "",
  "## 🔐 文件校验",
  "",
  '本次 Release 附带 `checksums.txt` 和 `release_manifest.json`。应用内更新会同时校验文件大小与 SHA256，校验失败不会启动安装。'
)

$releaseNotes = $releaseLines -join [Environment]::NewLine

$releaseNotes | Set-Content -Path $notesPath -Encoding UTF8

Write-Host "Created release manifest: $manifestPath"
Write-Host "Created checksums: $checksumsPath"
Write-Host "Created release notes: $notesPath"
